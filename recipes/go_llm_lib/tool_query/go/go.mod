module github.com/pgEdge/ellies-postgres-cookbook/recipes/go_llm_lib/tool_query/go

go 1.26.10

// --8<-- [start:deps]
// pgx is a pure Go driver and toolkit for PostgreSQL; the pgEdge Go LLM
// Library provides one client interface for several model providers.
require (
	github.com/jackc/pgx/v5 v5.12.0
	github.com/pgEdge/pgedge-go-llm-lib v0.6.0
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	golang.org/x/text v0.41.0 // indirect
)

// --8<-- [end:deps]
