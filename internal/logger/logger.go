package logger

import (
	"fmt"
	"log/slog"
	"os"
	"strings"

	"github.com/jasper0507/ripple/internal/config"
)

// New 创建一个 slog 日志记录器。
func New(cfg *config.LogConfig) (*slog.Logger, error) {
	// 将配置文件中的 string 类型转换为 slog.Level
	var level slog.Level
	if err := level.UnmarshalText([]byte(cfg.Level)); err != nil {
		return nil, fmt.Errorf("解析日志级别 %q 失败: %w", cfg.Level, err)
	}

	options := &slog.HandlerOptions{
		Level: level,
	}

	var handler slog.Handler
	switch strings.ToLower(cfg.Format) {
	case "json":
		handler = slog.NewJSONHandler(os.Stdout, options)
	case "text":
		handler = slog.NewTextHandler(os.Stdout, options)
	default:
		return nil, fmt.Errorf("不支持的日志格式 %q", cfg.Format)
	}

	return slog.New(handler), nil
}
