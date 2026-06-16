package trax

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	mqcommon "github.com/xshyft/trax/pkg/mq/common"
)

// TestIsMQHealthy_NilConnection verifies isMQHealthy returns false when
// the global RabbitMQ connection is nil.
func TestIsMQHealthy_NilConnection(t *testing.T) {
	// Save and restore global state
	origConn := mqcommon.RabbitMQConnection
	defer func() { mqcommon.RabbitMQConnection = origConn }()

	mqcommon.RabbitMQConnection = nil

	c := &defaultSagaCoordinator{}
	require.False(t, c.isMQHealthy(), "Should be unhealthy when connection is nil")
}

// TestIsReady_NotRunning verifies IsReady returns false when coordinator is not running.
func TestIsReady_NotRunning(t *testing.T) {
	c := &defaultSagaCoordinator{
		isRunning: false,
		dbHealthy: true,
	}
	require.False(t, c.IsReady(context.Background()))
}

// TestIsReady_DBUnhealthy verifies IsReady returns false when DB circuit is open.
func TestIsReady_DBUnhealthy(t *testing.T) {
	c := &defaultSagaCoordinator{
		isRunning: true,
		dbHealthy: false,
	}
	require.False(t, c.IsReady(context.Background()))
}

// TestIsReady_MQUnhealthy verifies IsReady returns false when MQ connection is nil.
func TestIsReady_MQUnhealthy(t *testing.T) {
	origConn := mqcommon.RabbitMQConnection
	defer func() { mqcommon.RabbitMQConnection = origConn }()

	mqcommon.RabbitMQConnection = nil

	c := &defaultSagaCoordinator{
		isRunning: true,
		dbHealthy: true,
	}
	require.False(t, c.IsReady(context.Background()))
}
