module github.com/pgEdge/ellies-postgres-cookbook/recipes/starfleet/connect_database/go

go 1.25.0

// --8<-- [start:deps]
// pgx is a pure Go driver and toolkit for PostgreSQL. The program calls
// the Starfleet API with the standard library alone.
require github.com/jackc/pgx/v5 v5.12.0

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	golang.org/x/text v0.41.0 // indirect
)

// --8<-- [end:deps]
