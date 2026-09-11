package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

const defaultSocketPath = "/var/run/docker.sock"

type DockerClient struct {
	socketPath string
	httpClient *http.Client
}

func NewClient() *DockerClient {
	return NewClientWithPath(defaultSocketPath)
}

func NewClientWithPath(socketPath string) *DockerClient {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, proto, addr string) (net.Conn, error) {
			return net.Dial("unix", socketPath)
		},
		DisableCompression: true,
	}

	return &DockerClient{
		socketPath: socketPath,
		httpClient: &http.Client{
			Transport: transport,
			Timeout:   10 * time.Second,
		},
	}
}

func (c *DockerClient) isSocketAvailable() bool {
	info, err := os.Stat(c.socketPath)
	if err != nil {
		return false
	}
	return info.Mode()&os.ModeSocket != 0
}

func (c *DockerClient) GetStatus() (*DockerStatus, error) {
	if !c.isSocketAvailable() {
		return &DockerStatus{
			Available:  false,
			Containers: []ContainerInfo{},
		}, nil
	}

	// 1. Get Docker version info
	var version string
	verResp, err := c.httpClient.Get("http://localhost/version")
	if err == nil {
		defer verResp.Body.Close()
		if verResp.StatusCode == http.StatusOK {
			var verData struct {
				Version string `json:"Version"`
			}
			if err := json.NewDecoder(verResp.Body).Decode(&verData); err == nil {
				version = verData.Version
			}
		}
	} else {
		// Socket file might exist but daemon isn't responding
		return &DockerStatus{
			Available:  false,
			Containers: []ContainerInfo{},
		}, nil
	}

	// 2. Get containers
	resp, err := c.httpClient.Get("http://localhost/containers/json?all=1")
	if err != nil {
		return &DockerStatus{
			Available:  true,
			Version:    version,
			Containers: []ContainerInfo{},
		}, nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return &DockerStatus{
			Available:  true,
			Version:    version,
			Containers: []ContainerInfo{},
		}, nil
	}

	type rawPort struct {
		IP          string `json:"IP"`
		PrivatePort int    `json:"PrivatePort"`
		PublicPort  int    `json:"PublicPort"`
		Type        string `json:"Type"`
	}

	type rawContainer struct {
		ID      string    `json:"Id"`
		Names   []string  `json:"Names"`
		Image   string    `json:"Image"`
		State   string    `json:"State"`
		Status  string    `json:"Status"`
		Created int64     `json:"Created"`
		Ports   []rawPort `json:"Ports"`
	}

	var rawList []rawContainer
	if err := json.NewDecoder(resp.Body).Decode(&rawList); err != nil {
		return nil, err
	}

	containers := make([]ContainerInfo, 0, len(rawList))
	for _, raw := range rawList {
		shortID := raw.ID
		if len(shortID) > 12 {
			shortID = shortID[:12]
		}

		name := ""
		if len(raw.Names) > 0 {
			name = strings.TrimPrefix(raw.Names[0], "/")
		}

		var portStrings []string
		for _, p := range raw.Ports {
			if p.PublicPort > 0 {
				portStrings = append(portStrings, fmt.Sprintf("%s:%d->%d/%s", p.IP, p.PublicPort, p.PrivatePort, p.Type))
			} else {
				portStrings = append(portStrings, fmt.Sprintf("%d/%s", p.PrivatePort, p.Type))
			}
		}

		containers = append(containers, ContainerInfo{
			ID:        shortID,
			Name:      name,
			Image:     raw.Image,
			State:     raw.State,
			Status:    raw.Status,
			CreatedAt: raw.Created,
			Ports:     portStrings,
		})
	}

	return &DockerStatus{
		Available:  true,
		Version:    version,
		Containers: containers,
	}, nil
}

func (c *DockerClient) ControlContainer(id string, action string) error {
	if !c.isSocketAvailable() {
		return fmt.Errorf("docker socket not available")
	}

	switch action {
	case "start", "stop", "restart":
	default:
		return fmt.Errorf("unsupported container action: %s", action)
	}

	url := fmt.Sprintf("http://localhost/containers/%s/%s", id, action)
	req, err := http.NewRequest(http.MethodPost, url, nil)
	if err != nil {
		return err
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusNotModified {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("docker api error (HTTP %d): %s", resp.StatusCode, string(body))
	}

	return nil
}

func (c *DockerClient) GetLogs(id string, tail int) (string, error) {
	if !c.isSocketAvailable() {
		return "", fmt.Errorf("docker socket not available")
	}

	if tail <= 0 {
		tail = 100
	}

	url := fmt.Sprintf("http://localhost/containers/%s/logs?stdout=1&stderr=1&tail=%d", id, tail)
	resp, err := c.httpClient.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("docker log error (HTTP %d): %s", resp.StatusCode, string(body))
	}

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	// Docker logs attach protocol includes 8-byte header per frame: [stream_type, 0, 0, 0, size1, size2, size3, size4]
	// Clean header if standard docker multiplexed stream
	var clean strings.Builder
	idx := 0
	for idx < len(raw) {
		if idx+8 <= len(raw) && (raw[idx] == 1 || raw[idx] == 2) {
			// standard multiplexed header
			size := int(raw[idx+4])<<24 | int(raw[idx+5])<<16 | int(raw[idx+6])<<8 | int(raw[idx+7])
			idx += 8
			if idx+size <= len(raw) {
				clean.Write(raw[idx : idx+size])
				idx += size
				continue
			}
		}
		clean.WriteByte(raw[idx])
		idx++
	}

	return clean.String(), nil
}
