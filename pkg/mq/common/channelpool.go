package mqcommon

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/xshyft/trax/pkg/common"
)

// ChannelPool manages a pool of RabbitMQ channels for thread-safe operations
// Each goroutine gets its own channel from the pool, eliminating race conditions
type ChannelPool struct {
	conn           *amqp.Connection
	channels       chan *amqp.Channel
	maxChannels    int
	mu             sync.Mutex
	closed         bool
	created        int // Track total channels created
	acquiredCount  int // Track total GetChannel calls
	releasedCount  int // Track total ReturnChannel calls
	currentlyInUse int // Track channels currently checked out
}

// NewChannelPool creates a new channel pool with the specified max channels
func NewChannelPool(conn *amqp.Connection, maxChannels int) (*ChannelPool, error) {
	if conn == nil {
		return nil, errors.New("connection is nil")
	}

	if maxChannels <= 0 {
		maxChannels = 500 // Default: 500 channels max
	}

	pool := &ChannelPool{
		conn:        conn,
		channels:    make(chan *amqp.Channel, maxChannels),
		maxChannels: maxChannels,
		closed:      false,
		created:     0,
	}

	// Pre-populate pool with initial channels (20% of max)
	initialChannels := maxChannels / 5
	if initialChannels < 1 {
		initialChannels = 1
	}

	for i := 0; i < initialChannels; i++ {
		ch, err := conn.Channel()
		if err != nil {
			// Close any channels we created before failing
			pool.Close()
			return nil, fmt.Errorf("failed to create initial channel %d: %w", i, err)
		}
		pool.channels <- ch
		pool.created++
	}

	common.L.Debug(fmt.Sprintf("[ChannelPool] Created: max=%d, initial=%d", maxChannels, initialChannels), common.F(context.Background())...)

	return pool, nil
}

// GetChannel retrieves a channel from the pool (or creates new one if needed)
// This is thread-safe and ensures each caller gets exclusive access to a channel
func (p *ChannelPool) GetChannel() (*amqp.Channel, error) {
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return nil, errors.New("channel pool is closed")
	}
	p.acquiredCount++
	acquireNum := p.acquiredCount
	p.mu.Unlock()

	common.L.Debug(fmt.Sprintf("[ChannelPool] ACQUIRE #%d (currently in use: %d/%d, acquired: %d, released: %d)",
		acquireNum, p.currentlyInUse, p.maxChannels, p.acquiredCount, p.releasedCount), common.F(context.Background())...)

	// Try to get from pool first (non-blocking)
	select {
	case ch := <-p.channels:
		// Verify channel is still open
		if ch.IsClosed() {
			p.mu.Lock()
			p.created--
			if p.created < 0 {
				p.created = 0
			}
			p.mu.Unlock()
			ClearPublisherForChannel(ch)
			common.L.Debug(fmt.Sprintf("[ChannelPool] ACQUIRE #%d: Retrieved closed channel from pool, discarding (created now: %d/%d)", acquireNum, p.created, p.maxChannels), common.F(context.Background())...)
			return p.GetChannel()
		}
		p.mu.Lock()
		p.currentlyInUse++
		inUse := p.currentlyInUse
		p.mu.Unlock()
		common.L.Debug(fmt.Sprintf("[ChannelPool] ACQUIRE #%d: SUCCESS from pool (now in use: %d/%d)", acquireNum, inUse, p.maxChannels), common.F(context.Background())...)
		return ch, nil
	default:
		// Pool is empty, need to create new channel or wait
		p.mu.Lock()

		if p.closed {
			p.mu.Unlock()
			return nil, errors.New("channel pool is closed")
		}

		if p.created >= p.maxChannels {
			// CRASH on channel pool exhaustion to surface leaks immediately.
			// With detached execution for sub-saga executors, channel usage should stay
			// well below the max. If we hit this, there's an active channel leak.
			inUse := p.currentlyInUse
			created := p.created
			acquired := p.acquiredCount
			released := p.releasedCount
			p.mu.Unlock()
			panic(fmt.Sprintf(
				"[ChannelPool] FATAL: channel pool exhausted! All %d channels are in use "+
					"(created: %d, in_use: %d, acquired: %d, released: %d). "+
					"This indicates a channel leak - channels are being acquired but not returned.",
				p.maxChannels, created, inUse, acquired, released))
		}

		// Create new channel (under lock to track created count)
		// If connection is closed, retry up to 3 times with 2s delay to allow
		// the reconnection handler to establish a new connection
		var ch *amqp.Channel
		var err error
		for attempt := 1; attempt <= 3; attempt++ {
			ch, err = p.conn.Channel()
			if err == nil {
				break
			}
			if !p.conn.IsClosed() {
				// Connection is open but channel creation failed for another reason
				break
			}
			if attempt < 3 {
				common.L.Warn(fmt.Sprintf(
					"[ChannelPool] ACQUIRE #%d: connection closed, waiting for reconnection (attempt %d/3)",
					acquireNum, attempt), common.F(context.Background())...)
				p.mu.Unlock()
				time.Sleep(2 * time.Second)
				p.mu.Lock()
				if p.closed {
					p.mu.Unlock()
					return nil, errors.New("channel pool is closed")
				}
			}
		}
		if err != nil {
			p.mu.Unlock()
			return nil, fmt.Errorf("failed to create new channel: %w", err)
		}

		p.created++
		p.currentlyInUse++
		created := p.created
		inUse := p.currentlyInUse
		p.mu.Unlock()

		common.L.Debug(fmt.Sprintf("[ChannelPool] ACQUIRE #%d: SUCCESS created new (total: %d/%d, in use: %d)",
			acquireNum, created, p.maxChannels, inUse), common.F(context.Background())...)

		return ch, nil
	}
}

// ReturnChannel returns a channel to the pool for reuse
// If pool is full or channel is closed, it will be discarded
func (p *ChannelPool) ReturnChannel(ch *amqp.Channel) {
	if ch == nil {
		common.L.Debug("[ChannelPool] RELEASE: Attempted to return nil channel", common.F(context.Background())...)
		return
	}

	p.mu.Lock()
	p.releasedCount++
	releaseNum := p.releasedCount

	if p.closed {
		// Pool is closed, close the channel
		p.mu.Unlock()
		ClearPublisherForChannel(ch)
		ch.Close()
		common.L.Debug(fmt.Sprintf("[ChannelPool] RELEASE #%d: Pool closed, closing channel (acquired: %d, released: %d)",
			releaseNum, p.acquiredCount, p.releasedCount), common.F(context.Background())...)
		return
	}

	// Don't return closed channels to pool — decrement created so new ones can be allocated
	if ch.IsClosed() {
		p.created--
		if p.created < 0 {
			p.created = 0
		}
		p.mu.Unlock()
		ClearPublisherForChannel(ch)
		common.L.Debug(fmt.Sprintf("[ChannelPool] RELEASE #%d: Discarded closed channel (created now: %d/%d, acquired: %d, released: %d)",
			releaseNum, p.created, p.maxChannels, p.acquiredCount, p.releasedCount), common.F(context.Background())...)
		return
	}

	p.currentlyInUse--
	inUse := p.currentlyInUse
	p.mu.Unlock()

	// Try to return to pool (non-blocking)
	select {
	case p.channels <- ch:
		common.L.Debug(fmt.Sprintf("[ChannelPool] RELEASE #%d: SUCCESS (now in use: %d/%d, acquired: %d, released: %d)",
			releaseNum, inUse, p.maxChannels, p.acquiredCount, p.releasedCount), common.F(context.Background())...)
	default:
		// Pool is full, close the channel
		ClearPublisherForChannel(ch)
		ch.Close()
		common.L.Debug(fmt.Sprintf("[ChannelPool] RELEASE #%d: Pool full, closing excess channel (acquired: %d, released: %d)",
			releaseNum, p.acquiredCount, p.releasedCount), common.F(context.Background())...)
	}
}

// Close closes all channels in the pool and marks pool as closed
func (p *ChannelPool) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.closed {
		return nil
	}

	p.closed = true
	close(p.channels)

	// Close all channels in pool
	count := 0
	for ch := range p.channels {
		if !ch.IsClosed() {
			ClearPublisherForChannel(ch)
			ch.Close()
		}
		count++
	}

	common.L.Debug(fmt.Sprintf("[ChannelPool] Closed: %d channels closed", count), common.F(context.Background())...)

	return nil
}

// DrainPool closes all available channels in the pool and resets the created counter
// so new channels are created lazily on demand. This MUST be called after ClearAllPublishers()
// to prevent stale confirm state: when publisher confirms are enabled on a channel via
// ch.Confirm() + ch.NotifyPublish(), clearing the publisher cache leaves orphaned NotifyPublish
// listeners on the channel. Reusing such channels causes confirmations to fan out to both the
// stale (unread) listener and the new one. Once the stale listener's buffer fills (100 msgs),
// the amqp library blocks ALL confirmations, causing publish timeouts.
//
// This should only be called when all consumers have been stopped (no checked-out channels).
func (p *ChannelPool) DrainPool() {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.closed {
		return
	}

	// Collect all channels from the pool (non-blocking reads)
	var channels []*amqp.Channel
	for {
		select {
		case ch := <-p.channels:
			channels = append(channels, ch)
		default:
			goto done
		}
	}
done:
	count := len(channels)
	p.created -= count
	if p.created < 0 {
		p.created = 0
	}

	// Close channels outside the critical section to avoid holding the mutex
	// while waiting for AMQP protocol-level close responses.
	// Use a goroutine with timeout: ch.Close() sends a channel.close command
	// and waits for the broker's close-ok. If a consumer goroutine hasn't fully
	// released the channel, this can block indefinitely.
	if count > 0 {
		go func() {
			for _, ch := range channels {
				ClearPublisherForChannel(ch)
				if !ch.IsClosed() {
					closeDone := make(chan struct{})
					go func(c *amqp.Channel) {
						defer close(closeDone)
						c.Close()
					}(ch)
					select {
					case <-closeDone:
						// closed successfully
					case <-time.After(5 * time.Second):
						common.L.Warn(fmt.Sprintf("[ChannelPool] DrainPool: ch.Close() timed out after 5s, skipping"),
							common.F(context.Background())...)
					}
				}
			}
		}()
	}

	common.L.Info(fmt.Sprintf("[ChannelPool] DrainPool: drained %d channels (created counter now: %d)",
		count, p.created), common.F(context.Background())...)
}

// UpdateConnection updates the pool's connection reference to a new valid connection.
// This should be called after a reconnection to allow the pool to create new channels
// on the fresh connection without having to recreate the entire pool.
func (p *ChannelPool) UpdateConnection(conn *amqp.Connection) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if conn == nil {
		return
	}
	p.conn = conn
	common.L.Info("[ChannelPool] Connection reference updated", common.F(context.Background())...)
}

// Stats returns pool statistics for monitoring
func (p *ChannelPool) Stats() map[string]int {
	p.mu.Lock()
	defer p.mu.Unlock()

	available := len(p.channels)
	inUse := p.created - available

	return map[string]int{
		"max":       p.maxChannels,
		"created":   p.created,
		"available": available,
		"in_use":    inUse,
	}
}

// IsClosed returns whether the pool has been closed
func (p *ChannelPool) IsClosed() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.closed
}
