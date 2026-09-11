package transport

import (
	"encoding/json"
	"time"

	"github.com/pulse/pulse-agent/internal/metrics"
	"github.com/pulse/pulse-agent/internal/processes"
	"github.com/pulse/pulse-agent/internal/services"
)

const ProtocolVersion = 1

type Envelope struct {
	Type      string          `json:"type"`
	Version   int             `json:"version"`
	Timestamp string          `json:"timestamp"`
	Payload   json.RawMessage `json:"payload"`
}

func NewEnvelope(msgType string, payload any) (*Envelope, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	return &Envelope{
		Type:      msgType,
		Version:   ProtocolVersion,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Payload:   data,
	}, nil
}

type HelloPayload struct {
	AgentID         string `json:"agent_id"`
	AgentVersion    string `json:"agent_version"`
	Hostname        string `json:"hostname"`
	OS              string `json:"os"`
	KernelVersion   string `json:"kernel_version"`
	Architecture    string `json:"architecture"`
	CPUCores        int    `json:"cpu_cores"`
	ProtocolVersion int    `json:"protocol_version"`
}

type HeartbeatPayload struct {
	AgentID       string `json:"agent_id"`
	UptimeSeconds int64  `json:"uptime_seconds"`
	Sequence      int64  `json:"sequence"`
}

type MetricsSnapshotPayload = metrics.MetricsSnapshot
type ProcessesSnapshotPayload = processes.ProcessesSnapshot
type ServicesSnapshotPayload = services.ServicesSnapshot
