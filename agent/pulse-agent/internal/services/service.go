package services

type ServiceInfo struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	LoadState   string `json:"load_state"`
	ActiveState string `json:"active_state"`
	SubState    string `json:"sub_state"`
}

type ServicesSnapshot struct {
	Services []ServiceInfo `json:"services"`
}

type Collector interface {
	CollectServices() ([]ServiceInfo, error)
}

type ServiceController interface {
	ControlService(name string, action string) error
}

