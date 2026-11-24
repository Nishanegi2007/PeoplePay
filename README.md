# PeoplePay — Payroll & Attendance Management

A connected payroll and attendance system built for the DBMS capstone. The React/Vite web app calls one Express API, which uses PostgreSQL for the canonical relational schema, payroll calculations, validation, reports, and access control.

## Capstone phase map

| Phase | Deliverables |
|---|---|
| 1 — Data model | `PeoplePay/backend/docs/DATA_MODEL.md`, `sql/01_schema.sql` |
| 2 — Procedural implementation | Salary/tax functions, payroll procedure, guards/triggers, and demo data in `sql/01_schema.sql` and `sql/02_seed.sql` |
| 3 — Reports & optimization | Monthly attendance, salary slip and late-mark queries in `sql/03_reports_and_plans.sql`; indexes defined in schema |
| 4 — Security & tests | HR/Admin and employee access checks in `backend/server.js`; SQL cases in `sql/04_test_cases.sql`; payroll and salary changes use transactions |
| 5 — Integrated UI | Role-aware React UI in `PeoplePay/frontend`; setup and operating notes below |

## Requirements

- Node.js 18 or later
- PostgreSQL 14 or later (the schema uses `btree_gist` for exclusion constraints)
- `psql` available on PATH for database scripts

## Start locally

1. Create the database and application login. For a local development database, from `psql` as a database administrator:

   ```sql
   CREATE USER payroll_app WITH PASSWORD 'change_me';
   CREATE DATABASE payroll_attendance OWNER payroll_app;
   ```

2. Load the schema and sample data from the backend folder:

   ```powershell
   cd PeoplePay/backend
   psql "postgresql://payroll_app:change_me@localhost:5432/payroll_attendance" -v ON_ERROR_STOP=1 -f sql/01_schema.sql
   psql "postgresql://payroll_app:change_me@localhost:5432/payroll_attendance" -v ON_ERROR_STOP=1 -f sql/02_seed.sql
   Copy-Item .env.example .env
   ```

   Edit `.env`; set `DATABASE_URL` to the same connection and replace `JWT_SECRET` with a long random value. The demo seed uses `pgcrypto` to hash passwords.

3. Install and start the API:

   ```powershell
   npm install
   npm start
   ```

4. In a second terminal, start the UI:

   ```powershell
   cd PeoplePay/frontend
   npm install
   npm run dev
   ```

   Open `http://localhost:5173`. To point the browser to another API host, define `VITE_API_URL` before `npm run dev` (default `http://localhost:5000/api`).

## Demo accounts

- HR/Admin: `admin@payroll.local` / `Admin123!`
- Employee: `aarav.sharma@example.com` / `Employee123!`

Other seeded employee accounts for Diya, Ishaan, and employees 5–10 are not created; HR can add accounts through SQL for demonstrations. Change demo passwords and JWT secret for any non-demo deployment. The app intentionally does not expose public signup or an account-creation endpoint.

## What to demonstrate

- Sign in as HR, record attendance, submit/review leave, create an employee/salary record, run a monthly payroll, and view reports.
- Sign in as the demo employee. The API scopes employee lists, attendance, leave, payroll and salary slips to the employee ID from the signed token; changing a request parameter cannot expose another employee.
- The payroll procedure is run inside an API transaction. Salary-history changes also use a transaction. A failed query rolls back before the connection is returned to the pool.

## Database scripts and verification

Run all scripts from `PeoplePay/backend` in this order: `sql/01_schema.sql`, `sql/02_seed.sql`, then `sql/04_test_cases.sql`. `npm test` runs API access-control tests without requiring PostgreSQL; `npm run test:sql` checks sample coverage, a known payroll result, and rejection of invalid salary, duplicate attendance, future attendance, and overlapping approved leave. SQL tests print PASS notices and stop on an unexpected result. The SQL test is not intended to reset an existing database.

For the Phase 3 plan comparison, first run `sql/05_performance_fixture.sql` to add idempotent synthetic history for the same 10 sample employees. Then run `sql/03_reports_and_plans.sql`; it shows the required reports and `EXPLAIN (ANALYZE, BUFFERS)` before and after adding the attendance date index. Capture both actual plan outputs for the submission; plan selection and timings depend on PostgreSQL version and hardware.

## Notes

- All monetary values use `numeric`, not floating point.
- Attendance has one row per employee per workday; approved leave periods cannot overlap.
- The tax model is intentionally transparent for coursework: taxable monthly gross multiplied by the effective salary tax rate. It is not intended as jurisdiction-specific tax advice.
- HR/Admin can view and manage workforce records, attendance, leave, salaries, and payroll. Employees have read-only access to their own records. Sensitive endpoints are protected in the API, not just hidden in the UI.
- SQL privileges are typically administered separately for production. This coursework app uses application-level RBAC and a database login for the API.

## Real-world use and scaling

For a small company, HR can record daily attendance, approve leave, maintain effective-dated salary rates, and generate monthly payslips from one PostgreSQL database. Employees use the same app to inspect only their own time and pay history. As the firm grows, keep the API stateless behind a load balancer, use a managed PostgreSQL service with backups and connection pooling, retain the employee/date indexes, and partition high-volume attendance and payroll tables by month or year. Multi-country deployments should add currency, timezone, holiday calendars, and jurisdiction-specific payroll rules before calculating actual pay.
