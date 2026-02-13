package main

import (
	"context"
	"embed"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed templates/*
var templateFS embed.FS

var templates = template.Must(template.ParseFS(templateFS, "templates/*.html"))

// Global connection pool (created once, shared across requests)
var pool *pgxpool.Pool

type PageData struct {
	Environment string
	DBHost      string
	DBName      string
	DBUser      string
	DBVersion   string
	Connected   bool
	Error       string
	Notes       []Note
	TableExists bool
}

type Note struct {
	ID        int
	Content   string
	CreatedAt string
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getConnString() string {
	host := getEnv("DB_HOST", "localhost")
	port := getEnv("DB_PORT", "5432")
	name := getEnv("DB_NAME", "appdb")
	user := getEnv("DB_USER", "appuser")
	pass := getEnv("DB_PASSWORD", "")
	sslmode := getEnv("DB_SSLMODE", "require")
	return fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=%s", host, port, name, user, pass, sslmode)
}

func initPool() error {
	config, err := pgxpool.ParseConfig(getConnString())
	if err != nil {
		return fmt.Errorf("parse config: %w", err)
	}
	config.MaxConns = 5
	config.MinConns = 1
	config.MaxConnLifetime = 30 * time.Minute
	config.MaxConnIdleTime = 5 * time.Minute

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err = pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return fmt.Errorf("create pool: %w", err)
	}
	return nil
}

func handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	data := PageData{
		Environment: getEnv("ENVIRONMENT", "unknown"),
		DBHost:      getEnv("DB_HOST", "localhost"),
		DBName:      getEnv("DB_NAME", "appdb"),
		DBUser:      getEnv("DB_USER", "appuser"),
	}

	ctx := r.Context()

	if pool == nil {
		data.Error = "Database connection pool not initialized"
		if err := templates.ExecuteTemplate(w, "index.html", data); err != nil {
			log.Printf("template error: %v", err)
		}
		return
	}

	conn, err := pool.Acquire(ctx)
	if err != nil {
		data.Error = fmt.Sprintf("Connection failed: %v", err)
		if err := templates.ExecuteTemplate(w, "index.html", data); err != nil {
			log.Printf("template error: %v", err)
		}
		return
	}
	defer conn.Release()
	data.Connected = true

	// Get PostgreSQL version
	err = conn.QueryRow(ctx, "SELECT version()").Scan(&data.DBVersion)
	if err != nil {
		data.Error = fmt.Sprintf("Version query failed: %v", err)
	}

	// Check if notes table exists
	var exists bool
	err = conn.QueryRow(ctx,
		"SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='notes')").Scan(&exists)
	if err == nil && exists {
		data.TableExists = true
		rows, err := conn.Query(ctx, "SELECT id, content, created_at::text FROM notes ORDER BY id DESC LIMIT 20")
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var n Note
				if err := rows.Scan(&n.ID, &n.Content, &n.CreatedAt); err == nil {
					data.Notes = append(data.Notes, n)
				}
			}
		}
	}

	if err := templates.ExecuteTemplate(w, "index.html", data); err != nil {
		log.Printf("template error: %v", err)
	}
}

func handleCreateTable(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}
	ctx := r.Context()
	conn, err := pool.Acquire(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer conn.Release()

	_, err = conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS notes (
			id SERIAL PRIMARY KEY,
			content TEXT NOT NULL,
			created_at TIMESTAMP DEFAULT NOW()
		)
	`)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func handleAddNote(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}
	content := r.FormValue("content")
	if content == "" {
		http.Redirect(w, r, "/", http.StatusSeeOther)
		return
	}

	ctx := r.Context()
	conn, err := pool.Acquire(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer conn.Release()

	_, err = conn.Exec(ctx, "INSERT INTO notes (content) VALUES ($1)", content)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

// handleLiveness returns 200 if the process is alive (no DB check)
func handleLiveness(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "ok")
}

// handleReadiness returns 200 only if the DB connection pool is healthy
func handleReadiness(w http.ResponseWriter, r *http.Request) {
	if pool == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprint(w, "pool not initialized")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if err := pool.Ping(ctx); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintf(w, "unhealthy: %v", err)
		return
	}
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "ok")
}

func main() {
	port := getEnv("PORT", "8080")

	// Initialize connection pool (non-fatal if DB isn't ready yet)
	if err := initPool(); err != nil {
		log.Printf("Warning: DB pool init failed (will retry on requests): %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", handleIndex)
	mux.HandleFunc("/create-table", handleCreateTable)
	mux.HandleFunc("/add-note", handleAddNote)
	mux.HandleFunc("/livez", handleLiveness)
	mux.HandleFunc("/healthz", handleReadiness)

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: mux,
	}

	// Graceful shutdown
	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("Starting server on :%s (env=%s, db=%s@%s/%s)",
			port,
			getEnv("ENVIRONMENT", "unknown"),
			getEnv("DB_USER", "appuser"),
			getEnv("DB_HOST", "localhost"),
			getEnv("DB_NAME", "appdb"),
		)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	<-done
	log.Println("Shutting down gracefully...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Shutdown error: %v", err)
	}

	if pool != nil {
		pool.Close()
	}
	log.Println("Server stopped")
}
