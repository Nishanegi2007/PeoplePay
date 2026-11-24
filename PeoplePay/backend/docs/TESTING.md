# Phase 4 — Verification record

Run automated database checks after loading the schema and sample data:

```powershell
cd merninventory/backend
$env:DATABASE_URL = 'postgresql://payroll_app:change_me@localhost:5432/payroll_attendance'
npm run test:sql
```

`sql/04_test_cases.sql` covers sample-data coverage, a known salary/tax result, negative salary, duplicate employee/day attendance, overlapping approved leave, and future attendance. Unexpected acceptance raises an exception and stops the script.

## Required role and transaction checks

| Case | Steps | Expected result | Result in this workspace |
|---|---|---|---|
| HR/Admin access | Sign in as `admin@payroll.local`; GET `/api/employees`; POST `/api/employees` | Employee list and creation succeed | Not run: PostgreSQL is not installed/configured in the current environment |
| Employee own-data scope | Sign in as `aarav.sharma@example.com`; GET `/api/attendance?employeeId=2`, `/api/payroll?employeeId=2`, `/api/employees` | Attendance/payroll ignore the foreign ID; employee list returns only Aarav | Not run: requires seeded PostgreSQL and running API |
| Unauthorized write | As employee POST `/api/employees`, POST `/api/attendance`, POST `/api/leaves`, PATCH `/api/leaves/1`, POST `/api/payroll/run` | HTTP 403 for each HR-only operation | Not run: requires running API |
| Missing/expired token | GET `/api/payroll` without Authorization | HTTP 401 | Not run: requires running API |
| Payroll transaction rollback | As HR request payroll for an invalid period such as `2025-03-02`; then query March payroll | API reports an error; existing March payroll rows remain unchanged | Not run: requires seeded PostgreSQL and running API |
| Negative amount / duplicate / overlapping leave / future attendance | Run `npm run test:sql` | SQL raises the relevant constraint/trigger error; script prints PASS notices | Not run: `psql` is not available in this workspace |

The “not run” entries are explicit: no PostgreSQL client/server was available during this rebuild, so the database script and end-to-end RBAC checks need to be run on the target machine. Record the observed HTTP status and SQL output here before submission.
