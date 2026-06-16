package mqcommon

import (
	"sync"
	"testing"

	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/xshyft/trax/pkg/common"
)

// Note: These are unit tests that don't require real RabbitMQ connection.
// Integration tests with real RabbitMQ should be in a separate test suite.

func TestNewChannelPool_NilConnection(t *testing.T) {
	pool, err := NewChannelPool(nil, 10)
	if err == nil {
		t.Error("NewChannelPool(nil) should return error")
	}
	if pool != nil {
		t.Error("NewChannelPool(nil) should return nil pool")
	}
	if err.Error() != "connection is nil" {
		t.Errorf("unexpected error message: %v", err)
	}
}

func TestNewChannelPool_DefaultMaxChannels(t *testing.T) {
	// Test that zero or negative maxChannels defaults to 20
	// This test can only verify the logic, not actual channel creation
	t.Skip("requires real RabbitMQ connection - run as integration test")
}

func TestChannelPoolStats(t *testing.T) {
	// Test the stats tracking logic without real channels
	pool := &ChannelPool{
		maxChannels: 10,
		created:     5,
		channels:    make(chan *amqp.Channel, 10),
		closed:      false,
	}

	// Add 3 mock channels to pool
	pool.channels <- nil
	pool.channels <- nil
	pool.channels <- nil

	stats := pool.Stats()

	if stats["max"] != 10 {
		t.Errorf("Expected max=10, got %d", stats["max"])
	}

	if stats["created"] != 5 {
		t.Errorf("Expected created=5, got %d", stats["created"])
	}

	if stats["available"] != 3 {
		t.Errorf("Expected available=3, got %d", stats["available"])
	}

	if stats["in_use"] != 2 {
		t.Errorf("Expected in_use=2, got %d (created=%d, available=%d)",
			stats["in_use"], stats["created"], stats["available"])
	}
}

func TestChannelPoolClose(t *testing.T) {
	// Initialize logger to prevent nil pointer dereference in Close()
	// common.L is used for logging in ChannelPool.Close()
	common.InitLogger()

	pool := &ChannelPool{
		channels: make(chan *amqp.Channel, 10),
		closed:   false,
	}

	// Pool should not be closed initially
	if pool.IsClosed() {
		t.Error("Pool should not be closed initially")
	}

	// Close pool
	err := pool.Close()
	if err != nil {
		t.Errorf("Close() returned error: %v", err)
	}

	if !pool.closed {
		t.Error("Pool should be marked as closed")
	}

	if !pool.IsClosed() {
		t.Error("IsClosed() should return true after Close()")
	}

	// Second close should be no-op
	err = pool.Close()
	if err != nil {
		t.Errorf("Second Close() returned error: %v", err)
	}
}

func TestChannelPoolReturnChannel_Nil(t *testing.T) {
	pool := &ChannelPool{
		channels: make(chan *amqp.Channel, 10),
		closed:   false,
	}

	// Returning nil should not panic
	pool.ReturnChannel(nil)
}

func TestChannelPoolReturnChannel_ClosedPool(t *testing.T) {
	// Test that returning a channel to a closed pool doesn't panic
	// This requires a mock channel
	t.Skip("requires mock AMQP channel - implement if needed")
}

func TestChannelPoolGetChannel_ClosedPool(t *testing.T) {
	pool := &ChannelPool{
		channels: make(chan *amqp.Channel, 10),
		closed:   true, // Already closed
	}

	ch, err := pool.GetChannel()
	if err == nil {
		t.Error("GetChannel() on closed pool should return error")
	}
	if ch != nil {
		t.Error("GetChannel() on closed pool should return nil channel")
	}
	if err.Error() != "channel pool is closed" {
		t.Errorf("unexpected error message: %v", err)
	}
}

func TestChannelPoolIsClosed(t *testing.T) {
	pool := &ChannelPool{
		channels: make(chan *amqp.Channel, 10),
		closed:   false,
	}

	if pool.IsClosed() {
		t.Error("New pool should not be closed")
	}

	pool.closed = true

	if !pool.IsClosed() {
		t.Error("Pool should be closed after setting closed=true")
	}
}

// Integration test placeholders - require real RabbitMQ connection

func TestChannelPool_Integration_GetReturn(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	t.Skip("requires real RabbitMQ connection - run as integration test")
}

func TestChannelPool_Integration_Concurrent(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	t.Skip("requires real RabbitMQ connection - run as integration test")

	// This test should verify:
	// - Multiple goroutines can safely get/return channels
	// - No race conditions occur
	// - Pool correctly manages max channels
}

func TestChannelPool_Integration_MaxCapacity(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	t.Skip("requires real RabbitMQ connection - run as integration test")

	// This test should verify:
	// - Pool doesn't create more than maxChannels
	// - GetChannel() blocks when at max and all channels in use
	// - GetChannel() unblocks when channel is returned
}

func TestChannelPool_Integration_ClosedChannelDetection(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	t.Skip("requires real RabbitMQ connection - run as integration test")

	// This test should verify:
	// - Pool detects closed channels in GetChannel()
	// - Pool doesn't return closed channels to pool
	// - Pool creates new channel when closed one encountered
}

func TestChannelPool_Integration_StressTest(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	t.Skip("requires real RabbitMQ connection - run as integration test")

	// This test should verify:
	// - 100 goroutines simultaneously getting/returning channels
	// - No panics or race conditions
	// - Pool stats remain consistent
}

// Example usage demonstrating thread-safety
func ExampleChannelPool_threadSafe() {
	// This example shows how channel pool provides thread-safe channel access
	// (Requires real RabbitMQ connection to run)

	// Multiple goroutines can safely get their own channels
	var wg sync.WaitGroup

	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()

			// Each goroutine gets its own channel from pool
			// ch, err := pool.GetChannel()
			// if err != nil { return }
			// defer pool.ReturnChannel(ch)

			// Now this goroutine has exclusive access to 'ch'
			// Safe to use without race conditions
			// ch.Publish(...)
		}(i)
	}

	wg.Wait()
	// Output:
}
