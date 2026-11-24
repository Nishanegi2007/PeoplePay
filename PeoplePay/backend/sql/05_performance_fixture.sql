-- Optional Phase 3 fixture: expands the same ten employees' history so the
-- attendance date index has enough rows to produce a useful EXPLAIN comparison.
-- Safe to rerun. Does not change the approved schema or the 2025 demo period.
INSERT INTO attendance(employee_id,work_date,check_in,check_out,status,notes)
SELECT e.employee_id,d::date,
  CASE WHEN extract(day from d)::int % 19=0 THEN NULL ELSE time '09:00' + make_interval(mins => (e.employee_id*3 % 12)) END,
  CASE WHEN extract(day from d)::int % 19=0 THEN NULL ELSE time '17:30' END,
  CASE WHEN extract(day from d)::int % 19=0 THEN 'ABSENT' ELSE 'PRESENT' END,
  'Synthetic historical performance fixture'
FROM employee e CROSS JOIN generate_series('2012-01-01'::date,'2024-12-31'::date,interval '1 day') d
WHERE extract(isodow from d)<6 AND extract(day from d)::int % 17 <> e.employee_id
ON CONFLICT(employee_id,work_date) DO NOTHING;
ANALYZE attendance;
