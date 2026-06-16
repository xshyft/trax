package trax

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xshyft/trax/pkg/common"
	"go.uber.org/zap"
)

// initTestLogger initializes the global logger for tests that call code
// using common.L (e.g., in-memory store's Listen/Unlisten).
func initTestLogger() {
	if common.L == nil {
		common.L = zap.NewNop()
	}
}

// TestSubscribeNotifications_FanOut verifies that multiple subscribers
// each receive notifications for their respective channels.
func TestSubscribeNotifications_FanOut(t *testing.T) {
	c := &defaultSagaCoordinator{}

	ch1 := c.subscribeNotifications("channel_a")
	ch2 := c.subscribeNotifications("channel_b")
	chAll := c.subscribeNotifications("") // empty = all channels

	// Simulate broadcaster sending a notification for channel_a
	notif := &StoreNotification{Channel: "channel_a", Payload: "test_payload"}
	c.notifSubsMutex.RLock()
	for _, sub := range c.notifSubs {
		if sub.channel == "" || sub.channel == notif.Channel {
			sub.ch <- notif
		}
	}
	c.notifSubsMutex.RUnlock()

	// ch1 (subscribed to channel_a) should receive it
	select {
	case got := <-ch1:
		require.Equal(t, "channel_a", got.Channel)
		require.Equal(t, "test_payload", got.Payload)
	case <-time.After(100 * time.Millisecond):
		t.Fatal("ch1 should have received notification")
	}

	// chAll (subscribed to all) should receive it
	select {
	case got := <-chAll:
		require.Equal(t, "channel_a", got.Channel)
	case <-time.After(100 * time.Millisecond):
		t.Fatal("chAll should have received notification")
	}

	// ch2 (subscribed to channel_b) should NOT receive it
	select {
	case <-ch2:
		t.Fatal("ch2 should NOT have received channel_a notification")
	case <-time.After(50 * time.Millisecond):
		// expected
	}
}

// TestSubscribeNotifications_ChannelFilter verifies that subscribers
// only receive notifications matching their channel filter.
func TestSubscribeNotifications_ChannelFilter(t *testing.T) {
	c := &defaultSagaCoordinator{}

	chSaga := c.subscribeNotifications("trax_saga_events")
	chTemplate := c.subscribeNotifications("trax_template_events")

	// Send saga event
	sagaNotif := &StoreNotification{Channel: "trax_saga_events", Payload: "saga_data"}
	c.notifSubsMutex.RLock()
	for _, sub := range c.notifSubs {
		if sub.channel == "" || sub.channel == sagaNotif.Channel {
			sub.ch <- sagaNotif
		}
	}
	c.notifSubsMutex.RUnlock()

	// Send template event
	tmplNotif := &StoreNotification{Channel: "trax_template_events", Payload: "template_data"}
	c.notifSubsMutex.RLock()
	for _, sub := range c.notifSubs {
		if sub.channel == "" || sub.channel == tmplNotif.Channel {
			sub.ch <- tmplNotif
		}
	}
	c.notifSubsMutex.RUnlock()

	// chSaga should only have saga event
	got := <-chSaga
	require.Equal(t, "trax_saga_events", got.Channel)
	select {
	case <-chSaga:
		t.Fatal("chSaga should not have template event")
	case <-time.After(50 * time.Millisecond):
	}

	// chTemplate should only have template event
	got = <-chTemplate
	require.Equal(t, "trax_template_events", got.Channel)
	select {
	case <-chTemplate:
		t.Fatal("chTemplate should not have saga event")
	case <-time.After(50 * time.Millisecond):
	}
}

// TestSubscribeNotifications_BufferFull verifies that notifications are
// dropped (not blocking) when a subscriber's buffer is full.
func TestSubscribeNotifications_BufferFull(t *testing.T) {
	c := &defaultSagaCoordinator{}

	ch := c.subscribeNotifications("test_channel")

	// Fill the buffer (capacity 100)
	for i := 0; i < 100; i++ {
		c.notifSubsMutex.RLock()
		for _, sub := range c.notifSubs {
			if sub.channel == "" || sub.channel == "test_channel" {
				select {
				case sub.ch <- &StoreNotification{Channel: "test_channel", Payload: "fill"}:
				default:
				}
			}
		}
		c.notifSubsMutex.RUnlock()
	}

	// Next send should not block (drops the message)
	done := make(chan struct{})
	go func() {
		c.notifSubsMutex.RLock()
		for _, sub := range c.notifSubs {
			if sub.channel == "" || sub.channel == "test_channel" {
				select {
				case sub.ch <- &StoreNotification{Channel: "test_channel", Payload: "overflow"}:
				default:
					// expected: buffer full, drop
				}
			}
		}
		c.notifSubsMutex.RUnlock()
		close(done)
	}()

	select {
	case <-done:
		// good — did not block
	case <-time.After(1 * time.Second):
		t.Fatal("Send should not block when buffer is full")
	}

	// Drain and verify we got exactly 100
	count := 0
	for {
		select {
		case <-ch:
			count++
		default:
			goto drained
		}
	}
drained:
	require.Equal(t, 100, count, "Should have exactly 100 buffered notifications")
}

// TestUnmarkAllStepsForTemplate verifies that step un-initialization
// correctly removes only the steps for the given template.
func TestUnmarkAllStepsForTemplate(t *testing.T) {
	c := &defaultSagaCoordinator{
		initializedSteps: map[string]bool{
			"cluster1:templateA:step1": true,
			"cluster1:templateA:step2": true,
			"cluster1:templateB:step1": true,
			"cluster2:templateA:step1": true,
		},
	}

	c.unmarkAllStepsForTemplate("cluster1", "templateA")

	require.False(t, c.initializedSteps["cluster1:templateA:step1"])
	require.False(t, c.initializedSteps["cluster1:templateA:step2"])
	require.True(t, c.initializedSteps["cluster1:templateB:step1"], "templateB should be untouched")
	require.True(t, c.initializedSteps["cluster2:templateA:step1"], "cluster2 should be untouched")
}

// TestGetTemplateReloadInterval verifies the default and env var override.
func TestGetTemplateReloadInterval(t *testing.T) {
	// Default should be 10s
	interval := getTemplateReloadInterval()
	require.Equal(t, 10*time.Second, interval)

	// With env var
	t.Setenv("TRAX_TEMPLATE_RELOAD_INTERVAL", "30s")
	interval = getTemplateReloadInterval()
	require.Equal(t, 30*time.Second, interval)

	// Invalid env var — falls back to default
	t.Setenv("TRAX_TEMPLATE_RELOAD_INTERVAL", "invalid")
	interval = getTemplateReloadInterval()
	require.Equal(t, 10*time.Second, interval)
}

// TestMultiChannelListen_InMemory verifies that in-memory store returns
// proper errors for LISTEN/NOTIFY (not supported).
func TestMultiChannelListen_InMemory(t *testing.T) {
	initTestLogger()
	store := NewInMemoryStore()

	err := store.Listen(nil, "test_channel")
	require.Error(t, err, "In-memory store should not support LISTEN")

	err = store.Unlisten(nil, "test_channel")
	require.Error(t, err, "In-memory store should not support UNLISTEN")

	ch := store.Notifications()
	require.Nil(t, ch, "In-memory store should return nil Notifications channel")
}

// TestSubscribeNotifications_ConcurrentAccess verifies thread safety of
// subscribeNotifications and notification dispatch.
func TestSubscribeNotifications_ConcurrentAccess(t *testing.T) {
	c := &defaultSagaCoordinator{}

	var wg sync.WaitGroup
	channels := make([]<-chan *StoreNotification, 10)

	// Create 10 subscribers concurrently
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			channels[idx] = c.subscribeNotifications("concurrent_test")
		}(i)
	}
	wg.Wait()

	require.Len(t, c.notifSubs, 10, "Should have 10 subscribers")

	// Send one notification — all 10 should receive it
	notif := &StoreNotification{Channel: "concurrent_test", Payload: "data"}
	c.notifSubsMutex.RLock()
	for _, sub := range c.notifSubs {
		if sub.channel == "" || sub.channel == notif.Channel {
			select {
			case sub.ch <- notif:
			default:
			}
		}
	}
	c.notifSubsMutex.RUnlock()

	for i, ch := range channels {
		select {
		case got := <-ch:
			require.Equal(t, "concurrent_test", got.Channel)
		case <-time.After(100 * time.Millisecond):
			t.Fatalf("Subscriber %d should have received notification", i)
		}
	}
}
