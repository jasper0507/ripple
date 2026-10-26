package middleware

import (
	"log/slog"
	"time"

	"github.com/gin-gonic/gin"
)

// RequestLogger 中间件，用于记录请求日志
func RequestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		// 不记录查询参数，避免密码、令牌等敏感输入进入日志。
		path := c.Request.URL.Path

		c.Next()

		slog.Info(
			"request",
			"method", c.Request.Method,
			"path", path,
			"status", c.Writer.Status(),
			"latency", time.Since(start),
			"client_ip", c.ClientIP(),
			"body_size", c.Writer.Size(),
		)

		for _, err := range c.Errors {
			slog.Error(
				"request error",
				"error", err.Error(),
			)
		}
	}
}
