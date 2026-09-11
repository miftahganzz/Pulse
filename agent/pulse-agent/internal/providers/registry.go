package providers

import (
	"context"
	"fmt"
	"sync"
	"time"
)

type DiscoveryResult struct {
	Timestamp time.Time           `json:"timestamp"`
	Services  []DiscoveredService `json:"services"`
}

type Registry struct {
	mu        sync.RWMutex
	providers map[string]Provider
}

func NewRegistry() *Registry {
	return &Registry{
		providers: make(map[string]Provider),
	}
}

func (r *Registry) Register(p Provider) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.providers[p.Type()] = p
}

type ProviderInfo struct {
	Type         string               `json:"type"`
	Capabilities []ProviderCapability `json:"capabilities"`
	State        ProviderState        `json:"state"`
}

func (r *Registry) ListProviders() []ProviderInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()
	infos := make([]ProviderInfo, 0, len(r.providers))
	for t, p := range r.providers {
		infos = append(infos, ProviderInfo{
			Type:         t,
			Capabilities: p.Capabilities(),
			State:        StateAvailable,
		})
	}
	return infos
}

func (r *Registry) DiscoverAll(ctx context.Context) (*DiscoveryResult, error) {
	r.mu.RLock()
	providersList := make([]Provider, 0, len(r.providers))
	for _, p := range r.providers {
		providersList = append(providersList, p)
	}
	r.mu.RUnlock()

	var allServices []DiscoveredService
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, p := range providersList {
		wg.Add(1)
		go func(prov Provider) {
			defer wg.Done()
			svcs, err := prov.Discover(ctx)
			if err == nil && len(svcs) > 0 {
				mu.Lock()
				allServices = append(allServices, svcs...)
				mu.Unlock()
			}
		}(p)
	}

	wg.Wait()

	return &DiscoveryResult{
		Timestamp: time.Now().UTC(),
		Services:  allServices,
	}, nil
}

func (r *Registry) CheckHealth(ctx context.Context, req MonitorRequest) HealthResult {
	r.mu.RLock()
	prov, exists := r.providers[req.Type]
	r.mu.RUnlock()

	if !exists {
		return HealthResult{
			ID:          req.ID,
			Status:      "unknown",
			Message:     fmt.Sprintf("unknown provider type: %s", req.Type),
			LastChecked: time.Now().UTC(),
		}
	}

	res, err := prov.Health(ctx, req.Target)
	if err != nil {
		return HealthResult{
			ID:          req.ID,
			Status:      "unknown",
			Message:     err.Error(),
			LastChecked: time.Now().UTC(),
		}
	}
	res.ID = req.ID // Ensure matching ID returned
	return res
}

func (r *Registry) CheckBatchHealth(ctx context.Context, reqs []MonitorRequest) []HealthResult {
	results := make([]HealthResult, len(reqs))
	var wg sync.WaitGroup

	for i, req := range reqs {
		wg.Add(1)
		go func(idx int, m MonitorRequest) {
			defer wg.Done()
			results[idx] = r.CheckHealth(ctx, m)
		}(i, req)
	}

	wg.Wait()
	return results
}
