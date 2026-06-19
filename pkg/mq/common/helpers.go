package mqcommon

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/xshyft/trax/pkg/common"
)

// MaxMessageRetries is the maximum number of times a message will be retried before being sent to DLQ
const MaxMessageRetries = 5

// Message header keys for retry tracking
const (
	RetryCountHeader   = "x-retry-count"
	RetryReasonHeader  = "x-retry-reason"
	FirstFailureHeader = "x-first-failure-time"
)

// GetRetryCount extracts the retry count from message headers
func GetRetryCount(headers amqp.Table) int {
	if headers == nil {
		return 0
	}
	if count, ok := headers[RetryCountHeader].(int32); ok {
		return int(count)
	}
	if count, ok := headers[RetryCountHeader].(int64); ok {
		return int(count)
	}
	if count, ok := headers[RetryCountHeader].(int); ok {
		return count
	}
	return 0
}

// IncrementRetryCount creates new headers with incremented retry count
func IncrementRetryCount(headers amqp.Table, reason string) amqp.Table {
	if headers == nil {
		headers = amqp.Table{}
	}

	// Create new headers map to avoid modifying original
	newHeaders := amqp.Table{}
	for k, v := range headers {
		newHeaders[k] = v
	}

	// Increment retry count
	currentCount := GetRetryCount(headers)
	newHeaders[RetryCountHeader] = int32(currentCount + 1)

	// Store retry reason
	newHeaders[RetryReasonHeader] = reason

	// Store first failure time if not already set
	if _, exists := headers[FirstFailureHeader]; !exists {
		newHeaders[FirstFailureHeader] = time.Now().Unix()
	}

	return newHeaders
}

// ShouldRetryMessage checks if a message should be retried based on retry count
func ShouldRetryMessage(headers amqp.Table, err error) bool {
	retryCount := GetRetryCount(headers)
	return retryCount < MaxMessageRetries
}

func GetExchangeNameByKey(key string) string {
	return fmt.Sprintf("x_%s", key)
}

func GetQueueNameByKey(key string) string {
	return fmt.Sprintf("q_%s", key)
}

func InitExchangeToMultipleQueues(ctx context.Context, exchangeName string, queueNames []string) error {
	if RabbitMQChannelPool == nil {
		return fmt.Errorf("rabbitmq channel pool not initialized")
	}

	ch, err := RabbitMQChannelPool.GetChannel()
	if err != nil {
		return fmt.Errorf("failed to get channel from pool: %w", err)
	}
	defer RabbitMQChannelPool.ReturnChannel(ch)

	err = ch.ExchangeDeclare(
		exchangeName, // name
		"fanout",     // type
		true,         // durable
		false,        // auto-delete
		false,        // internal
		false,        // no-wait
		nil,          // arguments
	)
	if err != nil {
		return err
	}
	for _, queueName := range queueNames {
		_, err := ch.QueueDeclare(
			queueName, // name
			true,      // durable
			false,     // delete when unused
			false,     // exclusive
			false,     // no-wait
			nil,       // arguments
		)
		if err != nil {
			return err
		}
		err = ch.QueueBind(
			queueName,
			"", // routing key
			exchangeName,
			false,
			nil,
		)
		if err != nil {
			return err
		}
	}
	return nil
}

func InitExchangeToMultipleQueuesByKey(ctx context.Context, key string, extraQueueOnlyKeys []string) error {
	exchangeName := GetExchangeNameByKey(key)
	queueNames := []string{}
	queueNames = append(queueNames, GetQueueNameByKey(key))
	for _, qKey := range extraQueueOnlyKeys {
		queueNames = append(queueNames, GetQueueNameByKey(qKey))
	}
	return InitExchangeToMultipleQueues(ctx, exchangeName, queueNames)
}

func PublishToExchangeByKey(ctx context.Context, key, messageType, contentType string, body []byte) error {
	exchangeName := GetExchangeNameByKey(key)
	return PublishToExchange(ctx, exchangeName, messageType, contentType, body)
}

func PublishToExchange(ctx context.Context, exchangeName, messageType, contentType string, body []byte) error {
	return Publish(ctx, exchangeName, messageType, contentType, body)
}

// PublishWithHeaders publishes a message with custom headers (e.g., for retry tracking)
func PublishWithHeaders(ctx context.Context, destName, messageType, contentType string, body []byte, headers amqp.Table) error {
	maxRetries := 3
	var lastErr error

	// Check if publisher confirms are enabled (default: enabled)
	useConfirms := os.Getenv("RABBITMQ_PUBLISHER_CONFIRMS") != "false"

	for attempt := 0; attempt < maxRetries; attempt++ {
		// Get channel from pool (thread-safe)
		if RabbitMQChannelPool == nil {
			lastErr = fmt.Errorf("rabbitmq channel pool not initialized")
			time.Sleep(time.Second * time.Duration(attempt+1))
			continue
		}

		ch, err := RabbitMQChannelPool.GetChannel()
		if err != nil {
			lastErr = fmt.Errorf("failed to get channel from pool: %w", err)
			time.Sleep(time.Second * time.Duration(attempt+1))
			continue
		}

		// Ensure channel is returned to pool when done
		// Use a variable to track if we should return it
		shouldReturn := true
		defer func() {
			if shouldReturn && ch != nil {
				RabbitMQChannelPool.ReturnChannel(ch)
			}
		}()

		// Decide whether to use confirms
		if useConfirms {
			err = publishWithConfirms(ctx, ch, destName, messageType, contentType, body, headers)
		} else {
			err = publishDirect(ctx, ch, destName, messageType, contentType, body, headers)
		}

		if err == nil {
			// Success — return channel to pool
			RabbitMQChannelPool.ReturnChannel(ch)
			shouldReturn = false
			return nil
		}

		// Check if retryable (handles all connection/channel errors)
		if IsRetryableError(err) {
			// Discard this channel — its publisher confirmation state is broken.
			// Clear the cached publisher so the next retry gets a fresh channel.
			ClearPublisherForChannel(ch)
			shouldReturn = false // Don't return stale channel to pool
			lastErr = err
			common.L.Warn(
				fmt.Sprintf("publish failed (retryable): %v, retry %d/%d", err, attempt+1, maxRetries),
				common.F(ctx)...)
			time.Sleep(time.Second * time.Duration(attempt+1))
			continue
		}

		// Non-retryable — return channel to pool (it's still usable)
		RabbitMQChannelPool.ReturnChannel(ch)
		shouldReturn = false

		// Non-retryable error (e.g., validation error, business logic error)
		return err
	}

	return fmt.Errorf("publish failed after %d attempts: %w", maxRetries, lastErr)
}

// Publish publishes a message without custom headers (backward compatible)
func Publish(ctx context.Context, destName, messageType, contentType string, body []byte) error {
	return PublishWithHeaders(ctx, destName, messageType, contentType, body, nil)
}

// publisherCache maps channels to their PublisherWithConfirms instances
// This ensures one publisher per channel, avoiding confirmation channel conflicts
var publisherCache sync.Map

// publisherCreationMutex protects publisher creation to prevent race conditions
// where multiple goroutines try to create publishers for the same channel
var publisherCreationMutex sync.Mutex

// ClearPublisherForChannel removes a publisher from the cache when its channel is closed
func ClearPublisherForChannel(ch *amqp.Channel) {
	if ch != nil {
		publisherKey := fmt.Sprintf("%p", ch)
		if cached, ok := publisherCache.Load(publisherKey); ok {
			publisher := cached.(*PublisherWithConfirms)
			publisher.Close() // Stop the router goroutine
		}
		publisherCache.Delete(publisherKey)
	}
}

// ClearAllPublishers removes all publishers from the cache
// This should be called when coordinators restart to prevent stale confirmations
// from buffered channels affecting new operations
func ClearAllPublishers() {
	publisherCache.Range(func(key, value interface{}) bool {
		publisher := value.(*PublisherWithConfirms)
		publisher.Close() // Stop the router goroutine
		publisherCache.Delete(key)
		return true // continue iterating
	})
}

// InitTopicExchange declares a durable topic exchange (idempotent).
func InitTopicExchange(ctx context.Context, exchangeName string) error {
	if RabbitMQChannelPool == nil {
		return fmt.Errorf("rabbitmq channel pool not initialized")
	}

	ch, err := RabbitMQChannelPool.GetChannel()
	if err != nil {
		return fmt.Errorf("failed to get channel from pool: %w", err)
	}
	defer RabbitMQChannelPool.ReturnChannel(ch)

	return ch.ExchangeDeclare(
		exchangeName, // name
		"topic",      // type
		true,         // durable
		false,        // auto-delete
		false,        // internal
		false,        // no-wait
		nil,          // arguments
	)
}

// InitQueueWithTopicBinding declares a durable queue and binds it to a topic exchange
// with the given routing key pattern. Supports wildcards: * (one word) and # (zero or more words).
func InitQueueWithTopicBinding(ctx context.Context, exchangeName, queueName, routingKeyPattern string) error {
	if RabbitMQChannelPool == nil {
		return fmt.Errorf("rabbitmq channel pool not initialized")
	}

	ch, err := RabbitMQChannelPool.GetChannel()
	if err != nil {
		return fmt.Errorf("failed to get channel from pool: %w", err)
	}
	defer RabbitMQChannelPool.ReturnChannel(ch)

	_, err = ch.QueueDeclare(
		queueName, // name
		true,      // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // no-wait
		nil,       // arguments
	)
	if err != nil {
		return fmt.Errorf("failed to declare queue '%s': %w", queueName, err)
	}

	err = ch.QueueBind(
		queueName,
		routingKeyPattern,
		exchangeName,
		false,
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to bind queue '%s' to exchange '%s' with key '%s': %w",
			queueName, exchangeName, routingKeyPattern, err)
	}

	return nil
}

// PublishWithRoutingKey publishes a message to a topic exchange with a specific routing key.
func PublishWithRoutingKey(ctx context.Context, exchangeName, routingKey, messageType, contentType string, body []byte, headers amqp.Table) error {
	maxRetries := 3
	var lastErr error

	// Check if publisher confirms are enabled (default: enabled)
	useConfirms := os.Getenv("RABBITMQ_PUBLISHER_CONFIRMS") != "false"

	for attempt := 0; attempt < maxRetries; attempt++ {
		// Get channel from pool (thread-safe)
		if RabbitMQChannelPool == nil {
			lastErr = fmt.Errorf("rabbitmq channel pool not initialized")
			time.Sleep(time.Second * time.Duration(attempt+1))
			continue
		}

		ch, err := RabbitMQChannelPool.GetChannel()
		if err != nil {
			lastErr = fmt.Errorf("failed to get channel from pool: %w", err)
			time.Sleep(time.Second * time.Duration(attempt+1))
			continue
		}

		// Ensure channel is returned to pool when done
		shouldReturn := true
		defer func() {
			if shouldReturn && ch != nil {
				RabbitMQChannelPool.ReturnChannel(ch)
			}
		}()

		if useConfirms {
			err = publishWithConfirmsRK(ctx, ch, exchangeName, routingKey, messageType, contentType, body, headers)
		} else {
			err = publishDirectRK(ctx, ch, exchangeName, routingKey, messageType, contentType, body, headers)
		}

		// Return channel immediately (don't wait for defer)
		RabbitMQChannelPool.ReturnChannel(ch)
		shouldReturn = false

		if err == nil {
			return nil
		}

		if IsRetryableError(err) {
			lastErr = err
			common.L.Warn(
				fmt.Sprintf("publish with routing key failed (retryable): %v, retry %d/%d", err, attempt+1, maxRetries),
				common.F(ctx)...)
			time.Sleep(time.Second * time.Duration(attempt+1))
			continue
		}

		return err
	}

	return fmt.Errorf("publish with routing key failed after %d attempts: %w", maxRetries, lastErr)
}

// publishWithConfirmsRK publishes with broker confirmation and a specific routing key
func publishWithConfirmsRK(ctx context.Context, ch *amqp.Channel, destName, routingKey, messageType, contentType string, body []byte, headers amqp.Table) error {
	timeout := 30 * time.Second
	if timeoutStr := os.Getenv("RABBITMQ_CONFIRM_TIMEOUT_SECONDS"); timeoutStr != "" {
		if seconds, err := strconv.Atoi(timeoutStr); err == nil && seconds > 0 {
			timeout = time.Duration(seconds) * time.Second
		}
	}

	publisherKey := fmt.Sprintf("%p", ch)

	if cached, ok := publisherCache.Load(publisherKey); ok {
		publisher := cached.(*PublisherWithConfirms)
		return publisher.PublishWithConfirm(ctx, destName, routingKey, false, false, amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  contentType,
			Type:         messageType,
			Body:         body,
			Timestamp:    time.Now(),
			Headers:      headers,
		})
	}

	publisherCreationMutex.Lock()

	if cached, ok := publisherCache.Load(publisherKey); ok {
		publisher := cached.(*PublisherWithConfirms)
		publisherCreationMutex.Unlock()
		return publisher.PublishWithConfirm(ctx, destName, routingKey, false, false, amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  contentType,
			Type:         messageType,
			Body:         body,
			Timestamp:    time.Now(),
			Headers:      headers,
		})
	}

	newPublisher, err := NewPublisherWithConfirms(ch, timeout)
	if err != nil {
		publisherCreationMutex.Unlock()
		return err
	}

	publisherCache.Store(publisherKey, newPublisher)
	publisherCreationMutex.Unlock()

	return newPublisher.PublishWithConfirm(
		ctx,
		destName,
		routingKey,
		false,
		false,
		amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  contentType,
			Type:         messageType,
			Body:         body,
			Timestamp:    time.Now(),
			Headers:      headers,
		},
	)
}

// publishDirectRK publishes without confirmation with a specific routing key
func publishDirectRK(ctx context.Context, ch *amqp.Channel, destName, routingKey, messageType, contentType string, body []byte, headers amqp.Table) error {
	return ch.PublishWithContext(
		ctx,
		destName,
		routingKey,
		false,
		false,
		amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  contentType,
			Type:         messageType,
			Body:         body,
			Timestamp:    time.Now(),
			Headers:      headers,
		},
	)
}

// publishWithConfirms publishes with broker confirmation
func publishWithConfirms(ctx context.Context, ch *amqp.Channel, destName, messageType, contentType string, body []byte, headers amqp.Table) error {
	timeout := 30 * time.Second
	if timeoutStr := os.Getenv("RABBITMQ_CONFIRM_TIMEOUT_SECONDS"); timeoutStr != "" {
		if seconds, err := strconv.Atoi(timeoutStr); err == nil && seconds > 0 {
			timeout = time.Duration(seconds) * time.Second
		}
	}

	// Get or create publisher for this channel
	// Use channel pointer as key to ensure one publisher per channel
	publisherKey := fmt.Sprintf("%p", ch)

	// First try to load existing publisher (fast path, no lock needed)
	if cached, ok := publisherCache.Load(publisherKey); ok {
		publisher := cached.(*PublisherWithConfirms)
		return publisher.PublishWithConfirm(ctx, destName, "", false, false, amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  contentType,
			Type:         messageType,
			Body:         body,
			Timestamp:    time.Now(),
			Headers:      headers,
		})
	}

	// No publisher found, need to create one
	// Use mutex to ensure only ONE goroutine creates publisher for this channel.
	// CRITICAL: Release the mutex BEFORE calling PublishWithConfirm, because publish
	// can block for up to 30s on confirmation timeout. Holding the global mutex during
	// publish serializes ALL publisher creations across all goroutines, turning a 5s
	// announcement interval into 60-180s when multiple submitters announce concurrently.
	publisherCreationMutex.Lock()

	// Double-check after acquiring lock (another goroutine may have created it)
	if cached, ok := publisherCache.Load(publisherKey); ok {
		publisher := cached.(*PublisherWithConfirms)
		publisherCreationMutex.Unlock()
		return publisher.PublishWithConfirm(ctx, destName, "", false, false, amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  contentType,
			Type:         messageType,
			Body:         body,
			Timestamp:    time.Now(),
			Headers:      headers,
		})
	}

	// Create new publisher (guaranteed to be called by only one goroutine per channel)
	newPublisher, err := NewPublisherWithConfirms(ch, timeout)
	if err != nil {
		publisherCreationMutex.Unlock()
		return err
	}

	// Store the newly created publisher and release the mutex BEFORE publishing
	publisherCache.Store(publisherKey, newPublisher)
	publisherCreationMutex.Unlock()

	return newPublisher.PublishWithConfirm(
		ctx,
		destName,
		"",
		false,
		false,
		amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  contentType,
			Type:         messageType,
			Body:         body,
			Timestamp:    time.Now(),
			Headers:      headers,
		},
	)
}

// publishDirect publishes without confirmation (legacy behavior)
func publishDirect(ctx context.Context, ch *amqp.Channel, destName, messageType, contentType string, body []byte, headers amqp.Table) error {
	return ch.PublishWithContext(
		ctx,
		destName,
		"",
		false,
		false,
		amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  contentType,
			Type:         messageType,
			Body:         body,
			Timestamp:    time.Now(),
			Headers:      headers,
		},
	)
}

// if both flags are set, republish will be used
type ConsumeOptions struct {
	RequeueNack   bool
	RepublishNack bool
	// CallbackTimeout overrides the default 180s callback timeout.
	// Set to 0 to use the default. Useful for consumers that handle
	// long-running operations (e.g., the step executor, sub-saga spawning/polling).
	CallbackTimeout time.Duration
}

func ConsumeQueueByKeyAsync(
	ctx context.Context,
	key string,
	cb func(ctx context.Context, messageType, contentType string, body []byte) error,
) func() {
	queueName := GetQueueNameByKey(key)
	return ConsumeQueueWithOptionsAsync(ctx, queueName, nil, cb)
}

func ConsumeQueueByKeyWithOptionsAsync(
	ctx context.Context,
	key string,
	options *ConsumeOptions,
	cb func(ctx context.Context, messageType, contentType string, body []byte) error,
) func() {
	queueName := GetQueueNameByKey(key)
	return ConsumeQueueWithOptionsAsync(ctx, queueName, options, cb)
}

// safeChannelCancel cancels a consumer without panicking on closed channel (T1-010)
func safeChannelCancel(ch *amqp.Channel, tag string, noWait bool) error {
	if ch == nil {
		return fmt.Errorf("channel is nil")
	}

	if ch.IsClosed() {
		// Channel already closed, cancellation is implicit
		return nil
	}

	// Recover from potential panic during cancel
	defer func() {
		if r := recover(); r != nil {
			common.L.Warn(
				fmt.Sprintf("panic during channel cancel (tag=%s): %v", tag, r),
				common.F(context.Background())...)
		}
	}()

	return ch.Cancel(tag, noWait)
}

func ConsumeQueueAsync(
	ctx context.Context,
	queueName string,
	cb func(ctx context.Context, messageType, contentType string, body []byte) error,
) func() {
	return ConsumeQueueWithOptionsAsync(ctx, queueName, nil, cb)
}

func ConsumeQueueWithOptionsAsync(
	ctx context.Context,
	queueName string,
	options *ConsumeOptions,
	cb func(ctx context.Context, messageType, contentType string, body []byte) error,
) func() {
	if options == nil {
		options = &ConsumeOptions{
			RequeueNack:   true,
			RepublishNack: false,
		}
	}

	// T1-012: Fix context inheritance - use new variable to avoid shadowing parent context
	var cancel func()
	consumerCtx, cancel := context.WithCancel(ctx)

	// Each consumer gets its own reconnection notification channel
	// cleanupReconnect MUST be called when the consumer exits to prevent listener leaks
	reconnectCh, cleanupReconnect := RegisterReconnectListener()

	go func() {
		defer func() {
			// Clean up the reconnection listener to prevent leaks
			cleanupReconnect()
			common.L.Warn(
				fmt.Sprintf("[%s] leaving consumer routine  ...", queueName), common.F(consumerCtx)...)
		}()
		cont := true
		for cont {
			select {
			case <-consumerCtx.Done():
				// Honor the cancel returned by ConsumeQueueByKeyAsync. Previously
				// this checked the parent ctx, which the cancel never touched —
				// so cancelConsumer() killed only the inner read goroutine and the
				// outer loop kept respawning a fresh one forever. That leak was
				// the root cause of the
				// "[%s] leaving msg reading loop" storm observed on
				// vp-agora-plgr1 (every fixreceiver Logon piled up one immortal
				// outer-loop consumer per participant per reconnect).
				cont = false
				break
			case <-reconnectCh:
				common.L.Debug(
					fmt.Sprintf("[%s] received reconnection signal, restarting consumer...", queueName),
					common.F(ctx)...)
				// Continue to next iteration to recreate consumer
				continue
			default:
				// Get channel from pool for this consumer instance
				if RabbitMQChannelPool == nil {
					common.L.Warn(
						fmt.Sprintf("[%s] channel pool not initialized, waiting...", queueName),
						common.F(ctx)...)
					time.Sleep(5 * time.Second)
					continue
				}

				ch, err := RabbitMQChannelPool.GetChannel()
				if err != nil {
					common.L.Warn(
						fmt.Sprintf("[%s] failed to get channel from pool: %v", queueName, err),
						common.F(ctx)...)
					time.Sleep(5 * time.Second)
					continue
				}

				// Channel will be returned at the end of this iteration
				// IMPORTANT: No defer here - must manually return before continue/break

				// T1-008: CRITICAL - Set up channel notifications BEFORE consuming
				// to avoid race condition where notification is lost
				closeCh := make(chan *amqp.Error, 1) // Buffered to avoid missing notification
				cancelCh := make(chan string, 1)     // T1-009: Consumer cancellation notification
				ch.NotifyClose(closeCh)
				ch.NotifyCancel(cancelCh)

				// Log channel state before consuming
				common.L.Debug(
					fmt.Sprintf("[%s] attempting to consume with channel (closed=%v)", queueName, ch.IsClosed()),
					common.F(consumerCtx)...)

				// T1-018: Set QoS prefetch limit to prevent message backlog accumulation
				// Prefetch count of 1 ensures each consumer processes one message at a time
				// This prevents goroutine leaks from accumulating unprocessed messages
				if qosErr := ch.Qos(
					1,     // prefetch count - process one message at a time
					0,     // prefetch size - 0 means no limit on message size
					false, // global - false means per-consumer limit
				); qosErr != nil {
					common.L.Warn(
						fmt.Sprintf("[%s] failed to set QoS: %v", queueName, qosErr),
						common.F(consumerCtx)...)
					RabbitMQChannelPool.ReturnChannel(ch)
					time.Sleep(5 * time.Second)
					continue
				}

				tag := common.SecureRandomString(32)
				msgs, err := ch.Consume(
					queueName, // queue name
					tag,       // consumer
					false,     // auto-ack
					false,     // exclusive
					false,     // no-local
					false,     // no-wait
					nil,       // args
				)
				if err != nil {
					common.L.Warn(
						fmt.Sprintf("[%s] consume error: %v (channel_closed=%v)", queueName, err, ch.IsClosed()),
						common.F(consumerCtx)...)

					// If channel is closed, wait for reconnection signal
					if ch.IsClosed() {
						common.L.Warn(
							fmt.Sprintf("[%s] detected closed channel, waiting for reconnection notification...", queueName),
							common.F(consumerCtx)...)
						RabbitMQChannelPool.ReturnChannel(ch) // Return channel before waiting
						select {
						case <-reconnectCh:
							common.L.Debug(
								fmt.Sprintf("[%s] received reconnection signal after consume error", queueName),
								common.F(consumerCtx)...)
							continue
						case <-time.After(10 * time.Second):
							common.L.Warn(
								fmt.Sprintf("[%s] timeout waiting for reconnection, retrying...", queueName),
								common.F(consumerCtx)...)
							continue
						}
					}

					RabbitMQChannelPool.ReturnChannel(ch) // Return channel before retrying
					time.Sleep(5 * time.Second)
					continue
				}

				common.L.Debug(
					fmt.Sprintf("[%s] successfully started consuming (tag=%s)", queueName, tag),
					common.F(consumerCtx)...)

				// T1-013, T1-014: Buffered channel to prevent deadlock
				waitCh := make(chan bool, 1)

				// Compute callback timeout once for use by both the inner goroutine and the outer wait.
				// This is the generic default consumer ceiling (180s). Consumers that run long steps
				// (e.g. the step executor, which enforces its own per-step deadline) pass an explicit
				// CallbackTimeout to widen this ceiling.
				callbackTimeout := 180 * time.Second
				if options.CallbackTimeout > 0 {
					callbackTimeout = options.CallbackTimeout
				}

				go func() {
					defer func() {
						common.L.Warn(
							fmt.Sprintf("[%s] leaving msg reading loop ...", queueName), common.F(consumerCtx)...)
						// T1-014: Use select with timeout to avoid blocking
						select {
						case waitCh <- true:
							// Successfully sent
						case <-time.After(5 * time.Second):
							common.L.Warn(
								fmt.Sprintf("[%s] WARNING: waitCh send timeout - receiver may be dead", queueName),
								common.F(consumerCtx)...)
						}
					}()
					cont := true
					common.L.Debug(
						fmt.Sprintf("[%s] starting msg reading loop ...", queueName), common.F(consumerCtx)...)
					for cont {
						select {
						case <-consumerCtx.Done():
							cont = false
							// T1-010: Use safe cancel to avoid panic on closed channel
							if err := safeChannelCancel(ch, tag, false); err != nil {
								common.L.Warn(
									fmt.Sprintf("[%s] failed to cancel consumer (tag=%s): %v", queueName, tag, err),
									common.F(consumerCtx)...)
							}
							break
						case closeErr := <-closeCh:
							common.L.Warn(
								fmt.Sprintf("[%s] channel closed: %v, will reconnect...", queueName, closeErr),
								common.F(consumerCtx)...)
							cont = false
							break
						case consumerTag := <-cancelCh:
							// T1-009: Handle server-initiated consumer cancellation
							common.L.Warn(
								fmt.Sprintf("[%s] consumer cancelled by server (tag=%s), will reconnect...",
									queueName, consumerTag),
								common.F(consumerCtx)...)
							cont = false
							break
						case <-reconnectCh:
							common.L.Debug(
								fmt.Sprintf("[%s] received reconnection signal in read loop", queueName),
								common.F(consumerCtx)...)
							cont = false
							// T1-010: Use safe cancel to avoid panic on closed channel
							if err := safeChannelCancel(ch, tag, false); err != nil {
								common.L.Warn(
									fmt.Sprintf("[%s] failed to cancel consumer (tag=%s): %v", queueName, tag, err),
									common.F(consumerCtx)...)
							}
							break
						case m, ok := <-msgs:
							if !ok {
								common.L.Warn(
									fmt.Sprintf("[%s] message channel closed", queueName),
									common.F(ctx)...)
								cont = false
								break
							}

							// T1-015: Add timeout protection to callback execution to prevent goroutine leaks
							// Execute callback with timeout monitoring
							// Callback timeout (default 180s, overridable via ConsumeOptions.CallbackTimeout)
							// bounds a single callback; long-running consumers (the step executor, LASER
							// blockchain ops via lcmgr) widen it explicitly.
							// This timeout must be less than the goroutine exit timeout (callbackTimeout + 10s)
							// to ensure callbacks complete before consumer restart
							type callbackResult struct {
								err error
							}
							resultCh := make(chan callbackResult, 1)

							// T1-017: Create cancellable context for callback to abort on timeout
							callbackCtx, callbackCancel := context.WithTimeout(ctx, callbackTimeout)
							defer callbackCancel()

							go func() {
								// Pass cancellable context to callback - this will abort database operations
								err := cb(callbackCtx, m.Type, m.ContentType, m.Body)
								select {
								case resultCh <- callbackResult{err: err}:
									// Successfully sent result
								default:
									// Receiver timed out, don't block
									common.L.Warn(
										fmt.Sprintf("[%s] callback completed but receiver already timed out (delivery_tag=%d)",
											queueName, m.DeliveryTag),
										common.F(ctx)...)
								}
							}()

							var err error
							select {
							case result := <-resultCh:
								// Callback completed within timeout
								err = result.err
							case <-time.After(callbackTimeout):
								// Callback exceeded timeout - CRITICAL
								common.L.Error(
									fmt.Sprintf("[%s] CRITICAL: callback timeout after %v (delivery_tag=%d) - NACKing for redelivery",
										queueName, callbackTimeout, m.DeliveryTag),
									common.F(ctx)...)
								// NACK message for redelivery since we don't know if processing completed
								if nackErr := m.Nack(false, true); nackErr != nil {
									common.L.Error(
										fmt.Sprintf("[%s] CRITICAL: Failed to NACK timed-out message (delivery_tag=%d): %v",
											queueName, m.DeliveryTag, nackErr),
										common.F(ctx)...)
								}
								// Skip normal ACK/NACK processing since we already NACKed
								continue
							}
							if err == nil {
								// ACK successful processing
								if ackErr := m.Ack(false); ackErr != nil {
									common.L.Error(
										fmt.Sprintf("[%s] CRITICAL: Failed to ACK message (delivery_tag=%d): %v - message will be redelivered",
											queueName, m.DeliveryTag, ackErr),
										common.F(ctx)...)
									// Message will be redelivered by RabbitMQ
									// This is acceptable - better than losing the message
								}
							} else {
								common.L.Error(fmt.Sprintf("failed to process message: %v", err), common.F(ctx)...)
								if options.RepublishNack {
									// Check if message should be retried (T0-006: Prevent infinite loops)
									if !ShouldRetryMessage(m.Headers, err) {
										retryCount := GetRetryCount(m.Headers)
										common.L.Warn(
											fmt.Sprintf("[%s] Message exceeded max retries (%d/%d) - DROPPING message (delivery_tag=%d)",
												queueName, retryCount, MaxMessageRetries, m.DeliveryTag),
											common.F(ctx)...)

										// ACK to remove poison message from queue
										if ackErr := m.Ack(false); ackErr != nil {
											common.L.Error(
												fmt.Sprintf("[%s] CRITICAL: Failed to ACK poison message (delivery_tag=%d): %v",
													queueName, m.DeliveryTag, ackErr),
												common.F(ctx)...)
										}
										// TODO: Send to DLX (Dead Letter Exchange) when implemented
										continue
									}

									// ACK original message FIRST - must succeed to avoid duplicates
									if ackErr := m.Ack(false); ackErr != nil {
										common.L.Error(
											fmt.Sprintf("[%s] CRITICAL: Failed to ACK before republish (delivery_tag=%d): %v - SKIPPING republish to avoid duplicates",
												queueName, m.DeliveryTag, ackErr),
											common.F(ctx)...)
										// DO NOT republish if ACK failed - would create guaranteed duplicate
										continue
									}

									// Increment retry count and republish with updated headers
									newHeaders := IncrementRetryCount(m.Headers, err.Error())
									retryCount := GetRetryCount(newHeaders)
									common.L.Warn(
										fmt.Sprintf("[%s] Republishing message with retry count %d/%d (delivery_tag=%d)",
											queueName, retryCount, MaxMessageRetries, m.DeliveryTag),
										common.F(ctx)...)

									if pubErr := PublishWithHeaders(ctx, queueName, m.Type, m.ContentType, m.Body, newHeaders); pubErr != nil {
										common.L.Error(
											fmt.Sprintf("[%s] CRITICAL: Failed to republish message: %v - MESSAGE MAY BE LOST",
												queueName, pubErr),
											common.F(ctx)...)
										// Message was ACKed but republish failed - message is lost
										// TODO: Send to DLX (Dead Letter Exchange) when implemented
									}
								} else {
									if options.RequeueNack {
										// NACK to requeue message for retry
										if nackErr := m.Nack(false, true); nackErr != nil {
											common.L.Error(
												fmt.Sprintf("[%s] CRITICAL: Failed to NACK message (delivery_tag=%d): %v - message stuck in unacked state",
													queueName, m.DeliveryTag, nackErr),
												common.F(ctx)...)
											// If NACK fails, message is stuck in unacked state
											// Channel close will force all unacked messages to requeue automatically
										}
									} else {
										// drop the message with a warning
										common.L.Warn(
											fmt.Sprintf(
												"message dropped: msg=<%+v>, err=<%+v>",
												m, err), common.F(ctx)...)
										// ACK to remove dropped message from queue
										if ackErr := m.Ack(false); ackErr != nil {
											common.L.Error(
												fmt.Sprintf("[%s] CRITICAL: Failed to ACK dropped message (delivery_tag=%d): %v - message will be redelivered",
													queueName, m.DeliveryTag, ackErr),
												common.F(ctx)...)
											// Message will be redelivered - will fail and be dropped again
											// Creating infinite loop - needs manual intervention or DLX
										}
									}
								}
								// fmt.Println(err.Error())
							}
						}
					}
				}()

				// T1-013: Add timeout to waitCh receive to prevent goroutine leaks
				// Timeout must be greater than callback timeout to allow callbacks to complete
				goroutineExitTimeout := callbackTimeout + 10*time.Second
				select {
				case <-waitCh:
					common.L.Debug(
						fmt.Sprintf("[%s] message reading loop exited normally", queueName),
						common.F(consumerCtx)...)
				case <-time.After(goroutineExitTimeout):
					common.L.Debug(
						fmt.Sprintf("[%s] WARNING: message reading loop exit timeout - potential goroutine leak", queueName),
						common.F(consumerCtx)...)
				}

				// Return channel to pool now that consumer is done
				RabbitMQChannelPool.ReturnChannel(ch)

				// Wait before retrying after disconnect
				time.Sleep(2 * time.Second)
			}
		}
	}()
	return cancel
}

// DeclareExclusiveQueueWithTopicBindings declares a non-durable, exclusive, auto-delete queue
// and binds it to a topic exchange with the given routing key patterns.
// Exclusive queues are automatically deleted when the declaring connection closes.
// Returns the AMQP channel (caller must manage its lifecycle — do NOT return to pool).
func DeclareExclusiveQueueWithTopicBindings(
	ctx context.Context,
	exchangeName string,
	queueName string,
	routingKeyPatterns []string,
) (*amqp.Channel, error) {
	if RabbitMQChannelPool == nil {
		return nil, fmt.Errorf("rabbitmq channel pool not initialized")
	}

	ch, err := RabbitMQChannelPool.GetChannel()
	if err != nil {
		return nil, fmt.Errorf("failed to get channel from pool: %w", err)
	}

	// Ensure the topic exchange exists (idempotent)
	err = ch.ExchangeDeclare(
		exchangeName,
		"topic", // type
		true,    // durable (exchange survives restart, queues don't)
		false,   // auto-delete
		false,   // internal
		false,   // no-wait
		nil,     // arguments
	)
	if err != nil {
		RabbitMQChannelPool.ReturnChannel(ch)
		return nil, fmt.Errorf("failed to declare topic exchange '%s': %w", exchangeName, err)
	}

	// Declare exclusive, auto-delete queue (non-durable)
	_, err = ch.QueueDeclare(
		queueName,
		false, // durable = false (exclusive queues are transient)
		true,  // delete when unused = true
		true,  // exclusive = true (auto-deleted when connection closes)
		false, // no-wait
		nil,   // arguments
	)
	if err != nil {
		RabbitMQChannelPool.ReturnChannel(ch)
		return nil, fmt.Errorf("failed to declare exclusive queue '%s': %w", queueName, err)
	}

	// Bind queue to exchange with each routing key pattern
	for _, rk := range routingKeyPatterns {
		err = ch.QueueBind(queueName, rk, exchangeName, false, nil)
		if err != nil {
			RabbitMQChannelPool.ReturnChannel(ch)
			return nil, fmt.Errorf("failed to bind queue '%s' to exchange '%s' with key '%s': %w",
				queueName, exchangeName, rk, err)
		}
	}

	common.L.Info(
		fmt.Sprintf("[exclusive-queue] declared queue '%s' bound to exchange '%s' with %d routing keys",
			queueName, exchangeName, len(routingKeyPatterns)),
		common.F(ctx)...)

	return ch, nil
}

// ConsumeExclusiveQueueAsync starts consuming from an exclusive queue. It handles
// reconnection by re-declaring the exclusive queue and re-binding to the exchange.
// Returns a delivery channel and a cancel function. The cancel function MUST be called
// on cleanup to release resources (closes AMQP channel, which auto-deletes the exclusive queue).
//
// Unlike ConsumeQueueAsync, this function:
//   - Creates its own exclusive queue (not pre-existing)
//   - Re-declares queue on reconnection (exclusive queues are lost on connection drop)
//   - Returns deliveries via a Go channel (not a callback) for easier integration with select loops
func ConsumeExclusiveQueueAsync(
	ctx context.Context,
	exchangeName string,
	queueName string,
	routingKeyPatterns []string,
) (<-chan []byte, func(), error) {
	// Initial declaration of the exclusive queue
	ch, err := DeclareExclusiveQueueWithTopicBindings(ctx, exchangeName, queueName, routingKeyPatterns)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to declare exclusive queue: %w", err)
	}

	// Set QoS prefetch=1
	if qosErr := ch.Qos(1, 0, false); qosErr != nil {
		ch.Close()
		return nil, nil, fmt.Errorf("failed to set QoS on exclusive queue '%s': %w", queueName, qosErr)
	}

	// Start initial consumer
	tag := common.SecureRandomString(32)
	deliveries, err := ch.Consume(
		queueName,
		tag,   // consumer tag
		true,  // auto-ack (exclusive queue, no need for manual ack)
		true,  // exclusive
		false, // no-local
		false, // no-wait
		nil,   // args
	)
	if err != nil {
		ch.Close()
		return nil, nil, fmt.Errorf("failed to start consuming exclusive queue '%s': %w", queueName, err)
	}

	// Buffered Go channel for delivering message bodies to caller
	msgCh := make(chan []byte, 100)

	// Internal context for coordinating shutdown
	cancelCtx, cancelFunc := context.WithCancel(ctx)

	// Register reconnect listener
	reconnectCh, cleanupReconnect := RegisterReconnectListener()

	// Track the current AMQP channel for cleanup
	var currentCh *amqp.Channel = ch
	var currentChMu sync.Mutex

	// Cancel function exposed to caller
	cancelOnce := sync.Once{}
	cancel := func() {
		cancelOnce.Do(func() {
			// Signal goroutine to stop
			cancelFunc()

			// Close the current AMQP channel (triggers exclusive queue auto-deletion)
			currentChMu.Lock()
			if currentCh != nil {
				currentCh.Close()
				currentCh = nil
			}
			currentChMu.Unlock()

			// Clean up reconnect listener
			cleanupReconnect()

			// Close the Go delivery channel
			// The goroutine may still be writing, so we rely on cancelCtx to stop it first.
			// The goroutine closes msgCh on exit.
		})
	}

	go func() {
		defer func() {
			close(msgCh)
			common.L.Info(
				fmt.Sprintf("[exclusive-queue] consumer goroutine exited for queue '%s'", queueName),
				common.F(ctx)...)
		}()

		currentDeliveries := deliveries
		closeCh := make(chan *amqp.Error, 1)
		cancelNotifyCh := make(chan string, 1)
		ch.NotifyClose(closeCh)
		ch.NotifyCancel(cancelNotifyCh)

		for {
			select {
			case <-cancelCtx.Done():
				common.L.Debug(
					fmt.Sprintf("[exclusive-queue] context cancelled for queue '%s'", queueName),
					common.F(ctx)...)
				return

			case closeErr := <-closeCh:
				common.L.Warn(
					fmt.Sprintf("[exclusive-queue] channel closed for queue '%s': %v, reconnecting...",
						queueName, closeErr),
					common.F(ctx)...)
				goto reconnect

			case consumerTag := <-cancelNotifyCh:
				common.L.Warn(
					fmt.Sprintf("[exclusive-queue] consumer cancelled by server for queue '%s' (tag=%s), reconnecting...",
						queueName, consumerTag),
					common.F(ctx)...)
				goto reconnect

			case <-reconnectCh:
				common.L.Info(
					fmt.Sprintf("[exclusive-queue] reconnection signal received for queue '%s', re-declaring...",
						queueName),
					common.F(ctx)...)
				goto reconnect

			case d, ok := <-currentDeliveries:
				if !ok {
					common.L.Warn(
						fmt.Sprintf("[exclusive-queue] delivery channel closed for queue '%s', reconnecting...",
							queueName),
						common.F(ctx)...)
					goto reconnect
				}
				// Send message body to the Go channel
				select {
				case msgCh <- d.Body:
				case <-cancelCtx.Done():
					return
				}
				continue
			}

		reconnect:
			// Check if we should stop
			select {
			case <-cancelCtx.Done():
				return
			default:
			}

			// Wait before attempting reconnection
			time.Sleep(2 * time.Second)

			// Re-declare exclusive queue (it was deleted when connection/channel closed)
			newCh, redeclareErr := DeclareExclusiveQueueWithTopicBindings(ctx, exchangeName, queueName, routingKeyPatterns)
			if redeclareErr != nil {
				common.L.Warn(
					fmt.Sprintf("[exclusive-queue] failed to re-declare queue '%s': %v, retrying...",
						queueName, redeclareErr),
					common.F(ctx)...)
				time.Sleep(5 * time.Second)
				goto reconnect
			}

			// Set QoS on new channel
			if qosErr := newCh.Qos(1, 0, false); qosErr != nil {
				common.L.Warn(
					fmt.Sprintf("[exclusive-queue] failed to set QoS on reconnected queue '%s': %v, retrying...",
						queueName, qosErr),
					common.F(ctx)...)
				newCh.Close()
				time.Sleep(5 * time.Second)
				goto reconnect
			}

			// Start consuming on new channel
			newTag := common.SecureRandomString(32)
			newDeliveries, consumeErr := newCh.Consume(
				queueName,
				newTag, // consumer tag
				true,   // auto-ack
				true,   // exclusive
				false,  // no-local
				false,  // no-wait
				nil,    // args
			)
			if consumeErr != nil {
				common.L.Warn(
					fmt.Sprintf("[exclusive-queue] failed to re-consume queue '%s': %v, retrying...",
						queueName, consumeErr),
					common.F(ctx)...)
				newCh.Close()
				time.Sleep(5 * time.Second)
				goto reconnect
			}

			// Update current channel reference
			currentChMu.Lock()
			currentCh = newCh
			currentChMu.Unlock()

			// Set up new notifications
			closeCh = make(chan *amqp.Error, 1)
			cancelNotifyCh = make(chan string, 1)
			newCh.NotifyClose(closeCh)
			newCh.NotifyCancel(cancelNotifyCh)
			currentDeliveries = newDeliveries

			common.L.Info(
				fmt.Sprintf("[exclusive-queue] successfully reconnected consumer for queue '%s' (tag=%s)",
					queueName, newTag),
				common.F(ctx)...)
		}
	}()

	common.L.Info(
		fmt.Sprintf("[exclusive-queue] started consuming queue '%s' (tag=%s)", queueName, tag),
		common.F(ctx)...)

	return msgCh, cancel, nil
}
