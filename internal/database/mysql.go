package database

import (
	"fmt"
	"log/slog"

	"github.com/jasper0507/ripple/internal/config"
	applog "github.com/jasper0507/ripple/internal/logger"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

// Open 初始化 MySQL 数据库连接，并配置底层连接池。
func Open(cfg *config.MySQLConfig) (*gorm.DB, error) {
	db, err := gorm.Open(mysql.Open(buildDSN(cfg)), &gorm.Config{
		Logger:         applog.NewGORM(slog.Default()),
		TranslateError: true,
	})
	if err != nil {
		return nil, fmt.Errorf("连接 MySQL 失败: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("获取数据库连接池失败: %w", err)
	}

	sqlDB.SetMaxOpenConns(cfg.MaxOpenConns)
	sqlDB.SetMaxIdleConns(cfg.MaxIdleConns)
	sqlDB.SetConnMaxLifetime(cfg.ConnMaxLifetime)

	return db, nil
}

// buildDSN 根据配置构建 MySQL DSN。
func buildDSN(cfg *config.MySQLConfig) string {
	return fmt.Sprintf(
		"%s:%s@tcp(%s:%d)/%s?charset=utf8mb4&parseTime=true&loc=Local&interpolateParams=%t",
		cfg.Username,
		cfg.Password,
		cfg.Host,
		cfg.Port,
		cfg.Database,
		cfg.InterpolateParams,
	)
}

// Close 关闭 GORM 底层的数据库连接池。
func Close(db *gorm.DB) error {
	if db == nil {
		return nil
	}

	sqlDB, err := db.DB()
	if err != nil {
		return fmt.Errorf("获取数据库连接池失败: %w", err)
	}

	if err := sqlDB.Close(); err != nil {
		return fmt.Errorf("关闭 MySQL 失败: %w", err)
	}

	return nil
}
