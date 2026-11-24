-- Phase 1: approved relational schema. Run on PostgreSQL 14+.
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE employee (
  employee_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  first_name varchar(60) NOT NULL, last_name varchar(60) NOT NULL,
  department varchar(80) NOT NULL, job_title varchar(80) NOT NULL,
  email varchar(254) NOT NULL UNIQUE, hire_date date NOT NULL,
  active boolean NOT NULL DEFAULT true,
  CHECK (email = lower(email))
);
CREATE TABLE app_user (
  user_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employee_id integer UNIQUE REFERENCES employee(employee_id) ON DELETE RESTRICT,
  email varchar(254) NOT NULL UNIQUE CHECK(email=lower(email)),
  password_hash text NOT NULL,
  role varchar(16) NOT NULL CHECK(role IN ('HR_ADMIN','EMPLOYEE')),
  active boolean NOT NULL DEFAULT true,
  CHECK ((role='HR_ADMIN' AND employee_id IS NULL) OR (role='EMPLOYEE' AND employee_id IS NOT NULL))
);
CREATE TABLE attendance (
  attendance_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employee_id integer NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
  work_date date NOT NULL, check_in time, check_out time,
  status varchar(12) NOT NULL DEFAULT 'PRESENT' CHECK(status IN ('PRESENT','ABSENT','REMOTE','LEAVE')),
  notes text,
  UNIQUE(employee_id,work_date),
  CHECK ((status IN ('ABSENT','LEAVE') AND check_in IS NULL AND check_out IS NULL) OR status IN ('PRESENT','REMOTE')),
  CHECK (check_out IS NULL OR check_in IS NOT NULL),
  CHECK (check_out IS NULL OR check_out > check_in)
);
CREATE TABLE leave_request (
  leave_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employee_id integer NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
  start_date date NOT NULL, end_date date NOT NULL,
  leave_type varchar(20) NOT NULL CHECK(leave_type IN ('ANNUAL','SICK','PERSONAL','UNPAID')),
  reason text, status varchar(12) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','REJECTED')),
  reviewed_by integer REFERENCES app_user(user_id) ON DELETE RESTRICT,
  reviewed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(end_date >= start_date),
  CHECK((status='PENDING' AND reviewed_by IS NULL AND reviewed_at IS NULL) OR status <> 'PENDING')
);
ALTER TABLE leave_request ADD CONSTRAINT no_overlapping_approved_leave
  EXCLUDE USING gist (employee_id WITH =, daterange(start_date,end_date,'[]') WITH &&) WHERE (status='APPROVED');
CREATE TABLE salary (
  salary_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employee_id integer NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
  effective_from date NOT NULL, effective_to date, base_monthly numeric(12,2) NOT NULL CHECK(base_monthly >= 0),
  allowance_monthly numeric(12,2) NOT NULL DEFAULT 0 CHECK(allowance_monthly >= 0),
  tax_rate numeric(5,4) NOT NULL DEFAULT 0.1000 CHECK(tax_rate BETWEEN 0 AND 0.5000),
  UNIQUE(employee_id,effective_from), CHECK(effective_to IS NULL OR effective_to >= effective_from),
  EXCLUDE USING gist (employee_id WITH =, daterange(effective_from,coalesce(effective_to,'infinity'::date),'[]') WITH &&)
);
CREATE TABLE payroll (
  payroll_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employee_id integer NOT NULL REFERENCES employee(employee_id) ON DELETE RESTRICT,
  salary_id bigint NOT NULL REFERENCES salary(salary_id) ON DELETE RESTRICT,
  period_start date NOT NULL, period_end date NOT NULL,
  base_pay numeric(12,2) NOT NULL CHECK(base_pay >= 0),
  allowance numeric(12,2) NOT NULL CHECK(allowance >= 0),
  unpaid_deduction numeric(12,2) NOT NULL CHECK(unpaid_deduction >= 0),
  tax_deduction numeric(12,2) NOT NULL CHECK(tax_deduction >= 0),
  gross_pay numeric(12,2) NOT NULL CHECK(gross_pay >= 0),
  net_pay numeric(12,2) NOT NULL CHECK(net_pay >= 0),
  generated_at timestamptz NOT NULL DEFAULT now(), generated_by integer REFERENCES app_user(user_id),
  UNIQUE(employee_id,period_start), CHECK(period_end >= period_start),
  CHECK(gross_pay=base_pay+allowance-unpaid_deduction),
  CHECK(net_pay=gross_pay-tax_deduction)
);

CREATE OR REPLACE FUNCTION calculate_tax(taxable numeric, rate numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE STRICT AS $$ SELECT round(greatest(taxable,0)*rate,2) $$;

CREATE OR REPLACE FUNCTION calculate_monthly_salary(base numeric, allowance numeric, unpaid_days numeric, tax_rate numeric)
RETURNS TABLE(gross numeric, tax numeric, net numeric) LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT round(base+allowance-round(base/30*unpaid_days,2),2),
         calculate_tax(round(base+allowance-round(base/30*unpaid_days,2),2),tax_rate),
         round(base+allowance-round(base/30*unpaid_days,2),2)-calculate_tax(round(base+allowance-round(base/30*unpaid_days,2),2),tax_rate)
$$;

CREATE OR REPLACE FUNCTION validate_attendance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.work_date > current_date THEN RAISE EXCEPTION 'Attendance cannot be recorded for a future date'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER attendance_date_guard BEFORE INSERT OR UPDATE ON attendance FOR EACH ROW EXECUTE FUNCTION validate_attendance();

CREATE OR REPLACE FUNCTION validate_leave() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.start_date > NEW.end_date THEN RAISE EXCEPTION 'Leave end date must be on or after start date'; END IF;
  IF NEW.status='APPROVED' AND EXISTS (
    SELECT 1 FROM leave_request l WHERE l.employee_id=NEW.employee_id AND l.leave_id<>coalesce(NEW.leave_id,-1)
      AND l.status='APPROVED' AND daterange(l.start_date,l.end_date,'[]') && daterange(NEW.start_date,NEW.end_date,'[]')
  ) THEN RAISE EXCEPTION 'Approved leave dates overlap'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER leave_overlap_guard BEFORE INSERT OR UPDATE ON leave_request FOR EACH ROW EXECUTE FUNCTION validate_leave();

CREATE OR REPLACE PROCEDURE generate_monthly_payroll(p_period date, p_generated_by integer)
LANGUAGE plpgsql AS $$
DECLARE month_end date := (date_trunc('month',p_period)+interval '1 month - 1 day')::date;
BEGIN
  IF p_period IS NULL OR p_period<>date_trunc('month',p_period)::date THEN RAISE EXCEPTION 'Period must be the first day of a month'; END IF;
  INSERT INTO payroll(employee_id,salary_id,period_start,period_end,base_pay,allowance,unpaid_deduction,tax_deduction,gross_pay,net_pay,generated_by)
  SELECT e.employee_id,s.salary_id,p_period,month_end,s.base_monthly,s.allowance_monthly,
    round(s.base_monthly/30*coalesce(u.days,0),2), calc.tax,calc.gross,calc.net,p_generated_by
  FROM employee e
  JOIN LATERAL (SELECT * FROM salary x WHERE x.employee_id=e.employee_id AND x.effective_from<=month_end
    AND (x.effective_to IS NULL OR x.effective_to>=p_period) ORDER BY x.effective_from DESC LIMIT 1) s ON true
  LEFT JOIN LATERAL (SELECT count(*)::numeric AS days FROM attendance a WHERE a.employee_id=e.employee_id
    AND a.work_date BETWEEN p_period AND month_end AND a.status='ABSENT') u ON true
  CROSS JOIN LATERAL calculate_monthly_salary(s.base_monthly,s.allowance_monthly,coalesce(u.days,0),s.tax_rate) calc
  WHERE e.active=true
  ON CONFLICT(employee_id,period_start) DO UPDATE SET salary_id=excluded.salary_id, period_end=excluded.period_end,
    base_pay=excluded.base_pay,allowance=excluded.allowance,unpaid_deduction=excluded.unpaid_deduction,
    tax_deduction=excluded.tax_deduction,gross_pay=excluded.gross_pay,net_pay=excluded.net_pay,
    generated_at=now(),generated_by=excluded.generated_by;
END $$;

CREATE VIEW monthly_attendance_summary AS
SELECT employee_id,date_trunc('month',work_date)::date AS month_start,
 count(*) FILTER(WHERE status IN ('PRESENT','REMOTE')) AS days_present,
 count(*) FILTER(WHERE status='ABSENT') AS days_absent,
 count(*) FILTER(WHERE check_in>time '09:15') AS late_marks,
 count(*) FILTER(WHERE status='LEAVE') AS leave_days
FROM attendance GROUP BY employee_id,date_trunc('month',work_date)::date;

CREATE INDEX attendance_date_employee_idx ON attendance(work_date,employee_id);
CREATE INDEX attendance_employee_date_idx ON attendance(employee_id,work_date);
CREATE INDEX leave_employee_dates_idx ON leave_request(employee_id,start_date,end_date);
CREATE INDEX payroll_period_employee_idx ON payroll(period_start,employee_id);
CREATE INDEX salary_effective_employee_idx ON salary(employee_id,effective_from DESC);
