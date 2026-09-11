package security

import (
	"testing"
)

func TestClassifyIP(t *testing.T) {
	tests := []struct {
		ip       string
		expected PortExposure
	}{
		{"127.0.0.1", ExposureLocalhost},
		{"::1", ExposureLocalhost},
		{"localhost", ExposurePublic},
		{"0.0.0.0", ExposurePublic},
		{"::", ExposurePublic},
		{"*", ExposurePublic},
		{"", ExposurePublic},
		{"100.64.0.5", ExposurePrivate},  // Tailscale CGNAT range
		{"100.115.92.1", ExposurePrivate}, // Tailscale CGNAT range
		{"192.168.1.100", ExposurePrivate},
		{"10.0.0.1", ExposurePrivate},
		{"172.16.0.5", ExposurePrivate},
		{"1.1.1.1", ExposurePublic},
		{"8.8.8.8", ExposurePublic},
	}

	for _, tt := range tests {
		got := ClassifyIP(tt.ip)
		if got != tt.expected {
			t.Errorf("ClassifyIP(%q) = %v, want %v", tt.ip, got, tt.expected)
		}
	}
}

func TestParseSSOutput(t *testing.T) {
	mockSS := []byte(`
tcp   LISTEN 0      128          0.0.0.0:22         0.0.0.0:*    users:(("sshd",pid=842,fd=3))
tcp   LISTEN 0      511          0.0.0.0:6379       0.0.0.0:*    users:(("redis-server",pid=1024,fd=6))
tcp   LISTEN 0      100        127.0.0.1:5432       0.0.0.0:*    users:(("postgres",pid=1100,fd=7))
udp   UNCONN 0      0            0.0.0.0:5353       0.0.0.0:*    users:(("avahi-daemon",pid=600,fd=12))
`)

	ports := parseSSOutput(mockSS)
	if len(ports) != 4 {
		t.Fatalf("expected 4 ports, got %d", len(ports))
	}

	// SSH on 22: public, but not flagged as dangerous database
	p0 := ports[0]
	if p0.Port != 22 || p0.ProcessName != "sshd" || p0.PID != 842 || p0.Exposure != ExposurePublic || p0.IsSensitive {
		t.Errorf("unexpected p0: %+v", p0)
	}

	// Redis on 6379: public, MUST be flagged as sensitive
	p1 := ports[1]
	if p1.Port != 6379 || p1.ProcessName != "redis-server" || p1.Exposure != ExposurePublic || !p1.IsSensitive {
		t.Errorf("expected sensitive public Redis, got: %+v", p1)
	}
	if p1.Recommendation == "" {
		t.Errorf("expected recommendation for Redis")
	}

	// Postgres on 5432: localhost, MUST NOT be flagged as sensitive public
	p2 := ports[2]
	if p2.Port != 5432 || p2.Exposure != ExposureLocalhost || p2.IsSensitive {
		t.Errorf("expected non-sensitive localhost Postgres, got: %+v", p2)
	}

	// UDP avahi on 5353
	p3 := ports[3]
	if p3.Port != 5353 || p3.Protocol != "udp" || p3.ProcessName != "avahi-daemon" {
		t.Errorf("unexpected p3: %+v", p3)
	}
}

func TestCollectPortsSnapshot(t *testing.T) {
	snap := CollectPortsSnapshot()
	if snap.Ports == nil {
		t.Errorf("expected non-nil ports array")
	}
	// On macOS or Linux during test, there should be at least 0 ports and valid counts
	if snap.PublicCount < 0 || snap.SensitiveCount < 0 {
		t.Errorf("negative counts: public=%d, sensitive=%d", snap.PublicCount, snap.SensitiveCount)
	}
}
