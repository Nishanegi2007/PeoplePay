-- Monthly attendance summary (one row per employee/month).
SELECT e.employee_id,e.first_name,e.last_name,s.month_start,s.days_present,s.days_absent,s.leave_days,s.late_marks
FROM monthly_attendance_summary s JOIN employee e USING(employee_id)
WHERE s.month_start='2025-03-01' ORDER BY e.employee_id;

-- Salary slip. Bind employee and first day of month in the application.
SELECT e.employee_id,e.first_name,e.last_name,e.department,p.period_start,p.period_end,
 p.base_pay,p.allowance,p.unpaid_deduction,p.gross_pay,p.tax_deduction,p.net_pay
FROM payroll p JOIN employee e USING(employee_id)
WHERE p.employee_id=1 AND p.period_start='2025-03-01';

-- Late marks report (arrival after 09:15).
SELECT e.employee_id,e.first_name,e.last_name,a.work_date,a.check_in
FROM attendance a JOIN employee e USING(employee_id)
WHERE a.check_in>time '09:15' AND a.work_date BETWEEN '2025-03-01' AND '2025-03-31'
ORDER BY a.work_date,e.employee_id;

-- Compare the plan with and without the reporting index. Run first, then create
-- attendance_date_employee_idx, ANALYZE, and run again; save both EXPLAIN ANALYZE outputs.
DROP INDEX IF EXISTS attendance_date_employee_idx;
EXPLAIN (ANALYZE,BUFFERS) SELECT employee_id,work_date,status FROM attendance
WHERE work_date BETWEEN '2025-03-01' AND '2025-03-31' ORDER BY work_date;
CREATE INDEX attendance_date_employee_idx ON attendance(work_date,employee_id);
ANALYZE attendance;
EXPLAIN (ANALYZE,BUFFERS) SELECT employee_id,work_date,status FROM attendance
WHERE work_date BETWEEN '2025-03-01' AND '2025-03-31' ORDER BY work_date;
