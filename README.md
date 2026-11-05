# Ellie's Postgres Cookbook

Ellie's Postgres Cookbook provides tested, multi-language code recipes for
PostgreSQL and pgEdge products.

[![Test](https://github.com/pgEdge/ellies-postgres-cookbook/actions/workflows/test.yml/badge.svg)](https://github.com/pgEdge/ellies-postgres-cookbook/actions/workflows/test.yml)

## Table of Contents

The documentation includes the following pages:

- [Introduction](docs/index.md)
- [Working with PostgreSQL](docs/postgresql/connect_and_query.md)
    - [Connecting to PostgreSQL and Running a Query](docs/postgresql/connect_and_query.md)
- [Contributing a Recipe](docs/contributing.md)
- [Changelog](docs/changelog.md)

Ellie's Postgres Cookbook is a library of how-to recipes for PostgreSQL and
pgEdge products. Each recipe explains how to accomplish a single task, step
by step, with the code for every step shown in Python, TypeScript, Java,
C#, Go, Rust, Ruby, and C, and in SQL or curl for the recipes that use
them. The published pages include their code directly from complete,
runnable programs in this repository, and continuous integration tests the
programs that each change touches.

## Installation

The recipes require a PostgreSQL server, and the toolchain for each
language to test. The documentation site requires Python 3 and
[Zensical](https://zensical.org/).

The following command installs Zensical:

```bash
pip install zensical
```

## Configuration

The example programs read the standard libpq environment variables; the
following commands configure the programs for a local server:

```bash
export PGHOST=localhost PGPORT=5432 PGDATABASE=postgres
export PGUSER=postgres PGPASSWORD=postgres
```

## Using Ellie's Postgres Cookbook

The test script builds and runs each program, and checks the output; the
following command tests the Python and Go programs for every recipe:

```bash
scripts/test_recipes.sh python go
```

The test script tests every language when the command specifies none. The
SQL recipes for the extensions and the recipes for the pgEdge products need
more than a plain PostgreSQL server: `scripts/start_test_server.sh` starts a
server with the extensions installed, and the recipes that need a product
or a service list what they need in their `requires.txt` files, which the
test script uses to skip a recipe whose variables are not set. The
[contributing guide](docs/contributing.md) describes how to run each set of
recipes.

## Documentation

The documentation source lives in the `docs` directory, and the code that
the pages include lives in the `recipes` directory. The following commands
check the tab groups, and then serve the site locally:

```bash
python3 scripts/check_tabs.py
zensical serve
```

The primary documentation site imports a rendered copy of the documentation
from the `published` branch, which a workflow regenerates after every
successful test run on `main`; for more information, see
[docs/contributing.md](docs/contributing.md).

## Support & Resources

For more information, visit [docs.pgedge.com](https://docs.pgedge.com).

To report an issue with the software, visit:
[GitHub Issues](https://github.com/pgEdge/ellies-postgres-cookbook/issues)

## Contributing

Contributions to the project are welcome; for more information, see
[docs/contributing.md](docs/contributing.md).

## License

The [PostgreSQL License](LICENSE.md) covers this project.
