package system

type NetworkStats struct {
	RxBytesPerSec   float64 `json:"rx_bytes_per_sec"`
	TxBytesPerSec   float64 `json:"tx_bytes_per_sec"`
	TotalRxBytes    uint64  `json:"total_rx_bytes"`
	TotalTxBytes    uint64  `json:"total_tx_bytes"`
	RxPacketsPerSec float64 `json:"rx_packets_per_sec"`
	TxPacketsPerSec float64 `json:"tx_packets_per_sec"`
	Errors          uint64  `json:"errors"`
}
