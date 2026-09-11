package security

import (
	"bufio"
	"bytes"
	"net"
	"os/exec"
	"regexp"
	"runtime"
	"strconv"
	"strings"
)

type PortExposure string

const (
	ExposurePublic    PortExposure = "public"
	ExposurePrivate   PortExposure = "private"
	ExposureLocalhost PortExposure = "localhost"
)

type ListeningPort struct {
	Port           int          `json:"port"`
	Protocol       string       `json:"protocol"` // "tcp" or "udp"
	IP             string       `json:"ip"`
	ProcessName    string       `json:"process_name"`
	PID            int          `json:"pid"`
	Exposure       PortExposure `json:"exposure"`
	IsSensitive    bool         `json:"is_sensitive"`
	Recommendation string       `json:"recommendation,omitempty"`
}

type FirewallStatus struct {
	IsActive        bool   `json:"is_active"`
	Type            string `json:"type"`             // "ufw", "iptables", "none"
	DefaultIncoming string `json:"default_incoming"` // "deny", "allow", "unknown"
}

type PortsSnapshot struct {
	Ports          []ListeningPort `json:"ports"`
	Firewall       FirewallStatus  `json:"firewall"`
	PublicCount    int             `json:"public_count"`
	SensitiveCount int             `json:"sensitive_count"`
}

var sensitivePortDescriptions = map[int]string{
	6379:  "Redis database exposed publicly. Unauthenticated Redis allows remote execution. Bind to 127.0.0.1 or Tailscale.",
	5432:  "PostgreSQL database exposed publicly. Bind to 127.0.0.1 or use private network / Tailscale.",
	3306:  "MySQL/MariaDB database exposed publicly. Bind to 127.0.0.1 or restrict with firewall.",
	27017: "MongoDB exposed publicly. Unauthenticated MongoDB databases are frequently targeted. Bind to 127.0.0.1.",
	9200:  "Elasticsearch exposed publicly. Protect behind reverse proxy or bind to 127.0.0.1.",
	11211: "Memcached exposed publicly. Vulnerable to amplification DDoS and data snooping. Bind to 127.0.0.1.",
	2375:  "Docker daemon unencrypted API exposed. Anyone can execute arbitrary root containers. Restrict immediately.",
	2376:  "Docker TLS API exposed. Ensure client certificate authentication is strictly enforced.",
	5672:  "RabbitMQ broker exposed publicly. Protect with firewall or private network.",
	15672: "RabbitMQ management UI exposed publicly. Restrict access to private VPN / Tailscale.",
	2379:  "Etcd cluster store exposed publicly. Ensure TLS client certs or bind to private IP.",
}

// ClassifyIP returns whether an IP is localhost, private, or public
func ClassifyIP(ipStr string) PortExposure {
	clean := strings.Trim(ipStr, "[]")
	if clean == "0.0.0.0" || clean == "::" || clean == "*" || clean == "" {
		return ExposurePublic
	}

	ip := net.ParseIP(clean)
	if ip == nil {
		return ExposurePublic
	}

	if ip.IsLoopback() {
		return ExposureLocalhost
	}

	// Check Tailscale CGNAT subnet 100.64.0.0/10
	_, tailscaleNet, _ := net.ParseCIDR("100.64.0.0/10")
	if tailscaleNet != nil && tailscaleNet.Contains(ip) {
		return ExposurePrivate
	}

	if ip.IsPrivate() || ip.IsLinkLocalUnicast() {
		return ExposurePrivate
	}

	return ExposurePublic
}

// CollectPortsSnapshot scans listening sockets and firewall configuration
func CollectPortsSnapshot() PortsSnapshot {
	ports := collectListeningSockets()
	fw := detectFirewall()

	publicCount := 0
	sensitiveCount := 0

	for _, p := range ports {
		if p.Exposure == ExposurePublic {
			publicCount++
		}
		if p.IsSensitive {
			sensitiveCount++
		}
	}

	return PortsSnapshot{
		Ports:          ports,
		Firewall:       fw,
		PublicCount:    publicCount,
		SensitiveCount: sensitiveCount,
	}
}

func collectListeningSockets() []ListeningPort {
	if runtime.GOOS == "darwin" {
		return collectDarwinSockets()
	}
	return collectLinuxSockets()
}

func collectLinuxSockets() []ListeningPort {
	// Try ss -tlpn -ulpn -H first
	out, err := exec.Command("ss", "-tlpn", "-ulpn", "-H").Output()
	if err == nil && len(out) > 0 {
		if ports := parseSSOutput(out); len(ports) > 0 {
			return ports
		}
	}

	// Fallback to netstat -tlpn -ulpn
	out, err = exec.Command("netstat", "-tlpn", "-ulpn").Output()
	if err == nil && len(out) > 0 {
		if ports := parseNetstatOutput(out); len(ports) > 0 {
			return ports
		}
	}

	return []ListeningPort{}
}

func parseSSOutput(data []byte) []ListeningPort {
	var result []ListeningPort
	seen := make(map[string]bool)

	scanner := bufio.NewScanner(bytes.NewReader(data))
	ssUsersRegex := regexp.MustCompile(`users:\(\("([^"]+)",pid=(\d+)`)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}

		proto := strings.ToLower(fields[0])
		if !strings.HasPrefix(proto, "tcp") && !strings.HasPrefix(proto, "udp") {
			continue
		}
		if strings.HasPrefix(proto, "tcp") {
			proto = "tcp"
		} else {
			proto = "udp"
		}

		var localAddr string
		for _, f := range fields {
			if strings.Contains(f, ":") && !strings.HasPrefix(f, "users:") && !strings.Contains(f, "*:*") {
				localAddr = f
				break
			}
		}

		if localAddr == "" {
			continue
		}

		ip, port := splitHostPort(localAddr)
		if port <= 0 {
			continue
		}

		key := proto + ":" + strconv.Itoa(port) + ":" + ip
		if seen[key] {
			continue
		}
		seen[key] = true

		procName := "unknown"
		pid := 0

		if match := ssUsersRegex.FindStringSubmatch(line); len(match) == 3 {
			procName = match[1]
			pid, _ = strconv.Atoi(match[2])
		}

		exposure := ClassifyIP(ip)
		isSensitive := false
		rec := ""

		if exposure == ExposurePublic {
			if desc, exists := sensitivePortDescriptions[port]; exists {
				isSensitive = true
				rec = desc
			}
		}

		result = append(result, ListeningPort{
			Port:           port,
			Protocol:       proto,
			IP:             ip,
			ProcessName:    procName,
			PID:            pid,
			Exposure:       exposure,
			IsSensitive:    isSensitive,
			Recommendation: rec,
		})
	}

	return result
}

func parseNetstatOutput(data []byte) []ListeningPort {
	var result []ListeningPort
	seen := make(map[string]bool)

	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "Proto") || line == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}

		proto := strings.ToLower(fields[0])
		if !strings.HasPrefix(proto, "tcp") && !strings.HasPrefix(proto, "udp") {
			continue
		}
		proto = proto[:3]

		localAddr := fields[3]
		ip, port := splitHostPort(localAddr)
		if port <= 0 {
			continue
		}

		key := proto + ":" + strconv.Itoa(port) + ":" + ip
		if seen[key] {
			continue
		}
		seen[key] = true

		procName := "unknown"
		pid := 0

		lastCol := fields[len(fields)-1]
		if strings.Contains(lastCol, "/") {
			parts := strings.SplitN(lastCol, "/", 2)
			pid, _ = strconv.Atoi(parts[0])
			if len(parts) > 1 {
				procName = parts[1]
			}
		}

		exposure := ClassifyIP(ip)
		isSensitive := false
		rec := ""

		if exposure == ExposurePublic {
			if desc, exists := sensitivePortDescriptions[port]; exists {
				isSensitive = true
				rec = desc
			}
		}

		result = append(result, ListeningPort{
			Port:           port,
			Protocol:       proto,
			IP:             ip,
			ProcessName:    procName,
			PID:            pid,
			Exposure:       exposure,
			IsSensitive:    isSensitive,
			Recommendation: rec,
		})
	}

	return result
}

func collectDarwinSockets() []ListeningPort {
	out, err := exec.Command("lsof", "-nP", "-iTCP", "-sTCP:LISTEN").Output()
	if err != nil {
		return []ListeningPort{}
	}

	var result []ListeningPort
	seen := make(map[string]bool)

	scanner := bufio.NewScanner(bytes.NewReader(out))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "COMMAND") || line == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 9 {
			continue
		}

		procName := fields[0]
		pid, _ := strconv.Atoi(fields[1])
		addrField := fields[8]

		ip, port := splitHostPort(addrField)
		if port <= 0 {
			continue
		}

		key := "tcp:" + strconv.Itoa(port) + ":" + ip
		if seen[key] {
			continue
		}
		seen[key] = true

		exposure := ClassifyIP(ip)
		isSensitive := false
		rec := ""

		if exposure == ExposurePublic {
			if desc, exists := sensitivePortDescriptions[port]; exists {
				isSensitive = true
				rec = desc
			}
		}

		result = append(result, ListeningPort{
			Port:           port,
			Protocol:       "tcp",
			IP:             ip,
			ProcessName:    procName,
			PID:            pid,
			Exposure:       exposure,
			IsSensitive:    isSensitive,
			Recommendation: rec,
		})
	}

	return result
}

func splitHostPort(addr string) (string, int) {
	addr = strings.TrimSpace(addr)
	lastColon := strings.LastIndex(addr, ":")
	if lastColon == -1 {
		return "", 0
	}

	host := addr[:lastColon]
	portStr := addr[lastColon+1:]

	port, err := strconv.Atoi(portStr)
	if err != nil {
		return "", 0
	}

	host = strings.Trim(host, "[]")
	if host == "*" {
		host = "0.0.0.0"
	}

	return host, port
}

func detectFirewall() FirewallStatus {
	if path, err := exec.LookPath("ufw"); err == nil && path != "" {
		out, err := exec.Command("ufw", "status", "verbose").Output()
		if err == nil {
			str := string(out)
			isActive := strings.Contains(str, "Status: active")
			defaultIncoming := "unknown"
			if strings.Contains(str, "deny (incoming)") {
				defaultIncoming = "deny"
			} else if strings.Contains(str, "allow (incoming)") {
				defaultIncoming = "allow"
			} else if strings.Contains(str, "reject (incoming)") {
				defaultIncoming = "reject"
			}
			return FirewallStatus{
				IsActive:        isActive,
				Type:            "ufw",
				DefaultIncoming: defaultIncoming,
			}
		}
	}

	if path, err := exec.LookPath("iptables"); err == nil && path != "" {
		out, err := exec.Command("iptables", "-L", "-n").Output()
		if err == nil && len(out) > 0 {
			str := string(out)
			defaultIncoming := "unknown"
			if strings.Contains(str, "Chain INPUT (policy DROP)") {
				defaultIncoming = "drop"
			} else if strings.Contains(str, "Chain INPUT (policy ACCEPT)") {
				defaultIncoming = "accept"
			}
			return FirewallStatus{
				IsActive:        true,
				Type:            "iptables",
				DefaultIncoming: defaultIncoming,
			}
		}
	}

	if runtime.GOOS == "darwin" {
		return FirewallStatus{
			IsActive:        true,
			Type:            "pf",
			DefaultIncoming: "deny",
		}
	}

	return FirewallStatus{
		IsActive:        false,
		Type:            "none",
		DefaultIncoming: "unknown",
	}
}
