package framework

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"testing"
)

// RabbitMQManagementClient provides access to RabbitMQ Management HTTP API
// for topology verification in E2E tests.
type RabbitMQManagementClient struct {
	baseURL  string
	username string
	password string
	client   *http.Client
}

// RabbitMQExchange represents a RabbitMQ exchange from the management API
type RabbitMQExchange struct {
	Name       string `json:"name"`
	Vhost      string `json:"vhost"`
	Type       string `json:"type"`
	Durable    bool   `json:"durable"`
	AutoDelete bool   `json:"auto_delete"`
}

// RabbitMQQueue represents a RabbitMQ queue from the management API
type RabbitMQQueue struct {
	Name       string `json:"name"`
	Vhost      string `json:"vhost"`
	Durable    bool   `json:"durable"`
	Messages   int    `json:"messages"`
	Consumers  int    `json:"consumers"`
	AutoDelete bool   `json:"auto_delete"`
}

// RabbitMQBinding represents a binding between an exchange and a queue
type RabbitMQBinding struct {
	Source          string `json:"source"`
	Vhost           string `json:"vhost"`
	Destination     string `json:"destination"`
	DestinationType string `json:"destination_type"`
	RoutingKey      string `json:"routing_key"`
}

// NewRabbitMQManagementClient creates a new client from environment variables.
// Required env vars: RABBITMQ_MANAGEMENT_URL, RABBITMQ_MANAGEMENT_USER, RABBITMQ_MANAGEMENT_PASS
func NewRabbitMQManagementClient(t *testing.T) *RabbitMQManagementClient {
	t.Helper()

	baseURL := os.Getenv("RABBITMQ_MANAGEMENT_URL")
	if baseURL == "" {
		t.Fatal("RABBITMQ_MANAGEMENT_URL environment variable not set")
	}
	username := os.Getenv("RABBITMQ_MANAGEMENT_USER")
	if username == "" {
		username = "guest"
	}
	password := os.Getenv("RABBITMQ_MANAGEMENT_PASS")
	if password == "" {
		password = "guest"
	}

	return &RabbitMQManagementClient{
		baseURL:  baseURL,
		username: username,
		password: password,
		client:   &http.Client{},
	}
}

func (c *RabbitMQManagementClient) doGet(path string) ([]byte, error) {
	url := fmt.Sprintf("%s%s", c.baseURL, path)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.SetBasicAuth(c.username, c.password)

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request to %s: %w", url, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %d from %s: %s", resp.StatusCode, url, string(body))
	}

	return body, nil
}

// ListExchanges returns all exchanges in the default vhost
func (c *RabbitMQManagementClient) ListExchanges(t *testing.T) []RabbitMQExchange {
	t.Helper()
	body, err := c.doGet("/api/exchanges/%2f")
	if err != nil {
		t.Fatalf("failed to list exchanges: %v", err)
	}
	var exchanges []RabbitMQExchange
	if err := json.Unmarshal(body, &exchanges); err != nil {
		t.Fatalf("failed to unmarshal exchanges: %v", err)
	}
	return exchanges
}

// ListQueues returns all queues in the default vhost
func (c *RabbitMQManagementClient) ListQueues(t *testing.T) []RabbitMQQueue {
	t.Helper()
	body, err := c.doGet("/api/queues/%2f")
	if err != nil {
		t.Fatalf("failed to list queues: %v", err)
	}
	var queues []RabbitMQQueue
	if err := json.Unmarshal(body, &queues); err != nil {
		t.Fatalf("failed to unmarshal queues: %v", err)
	}
	return queues
}

// ListBindingsForExchange returns all bindings sourced from the given exchange
func (c *RabbitMQManagementClient) ListBindingsForExchange(t *testing.T, exchangeName string) []RabbitMQBinding {
	t.Helper()
	body, err := c.doGet(fmt.Sprintf("/api/exchanges/%%2f/%s/bindings/source", exchangeName))
	if err != nil {
		t.Fatalf("failed to list bindings for exchange '%s': %v", exchangeName, err)
	}
	var bindings []RabbitMQBinding
	if err := json.Unmarshal(body, &bindings); err != nil {
		t.Fatalf("failed to unmarshal bindings: %v", err)
	}
	return bindings
}

// GetQueue returns details of a specific queue
func (c *RabbitMQManagementClient) GetQueue(t *testing.T, queueName string) *RabbitMQQueue {
	t.Helper()
	body, err := c.doGet(fmt.Sprintf("/api/queues/%%2f/%s", queueName))
	if err != nil {
		t.Fatalf("failed to get queue '%s': %v", queueName, err)
	}
	var queue RabbitMQQueue
	if err := json.Unmarshal(body, &queue); err != nil {
		t.Fatalf("failed to unmarshal queue: %v", err)
	}
	return &queue
}

// CountQueuesMatching counts queues whose names match the given regex pattern
func (c *RabbitMQManagementClient) CountQueuesMatching(t *testing.T, pattern string) int {
	t.Helper()
	re := regexp.MustCompile(pattern)
	queues := c.ListQueues(t)
	count := 0
	for _, q := range queues {
		if re.MatchString(q.Name) {
			count++
		}
	}
	return count
}

// GetQueuesMatching returns queues whose names match the given regex pattern
func (c *RabbitMQManagementClient) GetQueuesMatching(t *testing.T, pattern string) []RabbitMQQueue {
	t.Helper()
	re := regexp.MustCompile(pattern)
	queues := c.ListQueues(t)
	var matched []RabbitMQQueue
	for _, q := range queues {
		if re.MatchString(q.Name) {
			matched = append(matched, q)
		}
	}
	return matched
}

// GetExchangeByName finds an exchange by name, returns nil if not found
func (c *RabbitMQManagementClient) GetExchangeByName(t *testing.T, name string) *RabbitMQExchange {
	t.Helper()
	exchanges := c.ListExchanges(t)
	for _, ex := range exchanges {
		if ex.Name == name {
			return &ex
		}
	}
	return nil
}

// GetTotalQueueDepth returns the sum of message counts across all queues matching the pattern
func (c *RabbitMQManagementClient) GetTotalQueueDepth(t *testing.T, pattern string) int {
	t.Helper()
	queues := c.GetQueuesMatching(t, pattern)
	total := 0
	for _, q := range queues {
		total += q.Messages
	}
	return total
}
