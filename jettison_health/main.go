package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	redisDB      = 2
	redisTimeout = 5 * time.Second
)

// Config represents the application configuration
type Config struct {
	Redis struct {
		Host       string `json:"host"`
		Port       int    `json:"port"`
		SecretsDir string `json:"secrets_dir"`
	} `json:"redis"`
}

type HealthData struct {
	Beats          *int `json:"beats,omitempty"`
	Cap            *int `json:"cap,omitempty"`
	DepletionRate  *int `json:"depletion_rate,omitempty"`
	Init           *int `json:"init,omitempty"`
	ReplenishRate  *int `json:"replenish_rate,omitempty"`
	Running        *int `json:"running,omitempty"`
	Exit           *int `json:"exit,omitempty"`
	Health         *int `json:"health,omitempty"`
	Exists         bool `json:"exists"`
	MissingKeys    []string `json:"missing_keys,omitempty"`
}

type ServiceCategory struct {
	Service  string `json:"service"`
	Category string `json:"category"`
}

type ErrorResponse struct {
	Error   string   `json:"error"`
	Details string   `json:"details,omitempty"`
	Args    []string `json:"args,omitempty"`
}

type SuccessResponse struct {
	Data map[string]HealthData `json:"data"`
}

func main() {
	// Parse command line flags
	configPath := flag.String("config", "", "Path to configuration file")
	flag.Parse()

	// Check for config flag
	if *configPath == "" {
		printError("Configuration required", "Usage: jettison_health --config <config.json> <service>:<category> [<service>:<category> ...]", flag.Args())
		os.Exit(1)
	}

	// Load configuration
	config, err := loadConfig(*configPath)
	if err != nil {
		printError("Configuration error", err.Error(), nil)
		os.Exit(1)
	}

	// Get remaining arguments (service:category pairs)
	args := flag.Args()
	if len(args) < 1 {
		printError("No arguments provided", "Usage: jettison_health --config <config.json> <service>:<category> [<service>:<category> ...]", args)
		os.Exit(1)
	}

	// Parse service:category arguments
	targets, err := parseArguments(args)
	if err != nil {
		printError("Invalid arguments", err.Error(), args)
		os.Exit(1)
	}

	// Load Redis credentials
	username, password, err := loadRedisCredentials(config)
	if err != nil {
		printError("Credential loading failed", err.Error(), nil)
		os.Exit(1)
	}

	// Connect to Redis
	client := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", config.Redis.Host, config.Redis.Port),
		Username: username,
		Password: password,
		DB:       redisDB,
	})
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), redisTimeout)
	defer cancel()

	// Test connection
	if err := client.Ping(ctx).Err(); err != nil {
		printError("Redis connection failed", err.Error(), nil)
		os.Exit(1)
	}

	// Fetch health data for all targets
	allExists := true
	results := make(map[string]HealthData)

	for _, target := range targets {
		key := fmt.Sprintf("%s:%s", target.Service, target.Category)
		data := fetchHealthData(ctx, client, target.Service, target.Category)
		results[key] = data

		if !data.Exists {
			allExists = false
		}
	}

	// Output JSON
	response := SuccessResponse{Data: results}
	output, _ := json.MarshalIndent(response, "", "  ")
	fmt.Println(string(output))

	// Exit code: 0 if all exist, 1 if any missing
	if !allExists {
		os.Exit(1)
	}
	os.Exit(0)
}

func parseArguments(args []string) ([]ServiceCategory, error) {
	var targets []ServiceCategory
	seen := make(map[string]bool)

	for _, arg := range args {
		parts := strings.Split(arg, ":")
		if len(parts) != 2 {
			return nil, fmt.Errorf("invalid format '%s', expected <service>:<category>", arg)
		}

		service := strings.TrimSpace(parts[0])
		category := strings.TrimSpace(parts[1])

		if service == "" || category == "" {
			return nil, fmt.Errorf("empty service or category in '%s'", arg)
		}

		// Deduplicate
		key := fmt.Sprintf("%s:%s", service, category)
		if !seen[key] {
			targets = append(targets, ServiceCategory{
				Service:  service,
				Category: category,
			})
			seen[key] = true
		}
	}

	return targets, nil
}

func fetchHealthData(ctx context.Context, client *redis.Client, service, category string) HealthData {
	data := HealthData{Exists: true}
	var missingKeys []string

	// Define all keys to fetch
	keys := map[string]**int{
		"beats":          &data.Beats,
		"cap":            &data.Cap,
		"depletion_rate": &data.DepletionRate,
		"init":           &data.Init,
		"replenish_rate": &data.ReplenishRate,
		"running":        &data.Running,
		"exit":           &data.Exit,
		"health":         &data.Health,
	}

	// Fetch each key
	for keyName, targetPtr := range keys {
		redisKey := fmt.Sprintf("%s:__healthpool__%s_%s", service, category, keyName)
		val, err := client.Get(ctx, redisKey).Int()

		if err == redis.Nil {
			missingKeys = append(missingKeys, keyName)
		} else if err == nil {
			*targetPtr = &val
		}
	}

	// Mark as not existing if any required key is missing
	if len(missingKeys) > 0 {
		data.Exists = false
		data.MissingKeys = missingKeys
	}

	return data
}

// loadConfig reads and parses the JSON configuration file
func loadConfig(configPath string) (*Config, error) {
	var config Config
	configData, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	if err := json.Unmarshal(configData, &config); err != nil {
		return nil, fmt.Errorf("failed to parse JSON config: %w", err)
	}

	// Validate required fields
	if config.Redis.Host == "" {
		return nil, fmt.Errorf("redis.host is required")
	}
	if config.Redis.Port == 0 {
		return nil, fmt.Errorf("redis.port is required")
	}
	if config.Redis.SecretsDir == "" {
		return nil, fmt.Errorf("redis.secrets_dir is required")
	}

	return &config, nil
}

// loadRedisCredentials loads username and password from the secrets directory
// Username is inferred from the directory basename
// Password is read from the "password" file in the directory
func loadRedisCredentials(config *Config) (username, password string, err error) {
	if config.Redis.SecretsDir == "" {
		return "", "", fmt.Errorf("redis.secrets_dir is required")
	}

	// Username = basename of secrets directory
	username = filepath.Base(config.Redis.SecretsDir)

	// Read password from file
	passwordPath := filepath.Join(config.Redis.SecretsDir, "password")
	passwordData, err := os.ReadFile(passwordPath)
	if err != nil {
		return "", "", fmt.Errorf("failed to read password file %s: %w", passwordPath, err)
	}

	password = strings.TrimSpace(string(passwordData))
	if password == "" {
		return "", "", fmt.Errorf("password file %s is empty", passwordPath)
	}

	return username, password, nil
}

func printError(errorMsg, details string, args []string) {
	resp := ErrorResponse{
		Error:   errorMsg,
		Details: details,
		Args:    args,
	}
	output, _ := json.MarshalIndent(resp, "", "  ")
	fmt.Println(string(output))
}
