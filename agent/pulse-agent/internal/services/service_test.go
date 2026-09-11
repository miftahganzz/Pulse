package services_test

import (
	"testing"

	"github.com/pulse/pulse-agent/internal/services"
)

func TestCollectServices(t *testing.T) {
	c := services.NewCollector()
	svcs, err := c.CollectServices()
	if err != nil {
		t.Fatalf("failed to collect services: %v", err)
	}

	if len(svcs) == 0 {
		t.Fatal("expected at least 1 service, got 0")
	}

	t.Logf("Found %d services", len(svcs))
	for i, s := range svcs {
		if i < 5 {
			t.Logf("Service: %s (Active: %s, Sub: %s, Desc: %s)",
				s.Name, s.ActiveState, s.SubState, s.Description)
		}
	}
}

func TestControlServiceValidation(t *testing.T) {
	c := services.NewCollector()
	ctrl, ok := c.(services.ServiceController)
	if !ok {
		t.Skip("Collector does not implement ServiceController")
	}

	// Valid action on Darwin should return nil or exec error
	if err := ctrl.ControlService("test.service", "restart"); err != nil {
		t.Errorf("unexpected error on valid action: %v", err)
	}

	// Invalid action should return error
	if err := ctrl.ControlService("test.service", "destroy"); err == nil {
		t.Error("expected error with invalid action 'destroy', got nil")
	}
}

