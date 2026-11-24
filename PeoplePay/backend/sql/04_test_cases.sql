-- Run after 01_schema.sql and 02_seed.sql. Every invalid case must raise an error.
DO $$ BEGIN
  IF (SELECT count(*) FROM employee) < 10 THEN RAISE EXCEPTION 'FAIL: expected 10 employees'; END IF;
  IF (SELECT count(DISTINCT period_start) FROM payroll) < 3 THEN RAISE EXCEPTION 'FAIL: expected payroll for 3 months'; END IF;
  IF (SELECT count(*) FROM monthly_attendance_summary WHERE month_start BETWEEN '2025-01-01' AND '2025-03-01') < 30 THEN RAISE EXCEPTION 'FAIL: monthly report missing'; END IF;
  IF (SELECT net FROM calculate_monthly_salary(30000,3000,1,.10)) <> 28800 THEN RAISE EXCEPTION 'FAIL: salary/tax calculation'; END IF;
  RAISE NOTICE 'PASS: 10+ employees, 3 months payroll, report coverage';
END $$;
DO $$ BEGIN
  BEGIN INSERT INTO salary(employee_id,effective_from,base_monthly) VALUES(1,'2025-01-01',-1); RAISE EXCEPTION 'FAIL: negative salary accepted';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: negative salary rejected'; END;
  BEGIN INSERT INTO attendance(employee_id,work_date,status) VALUES(1,'2025-03-03','PRESENT'); RAISE EXCEPTION 'FAIL: duplicate attendance accepted';
  EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS: duplicate attendance rejected'; END;
  BEGIN INSERT INTO leave_request(employee_id,start_date,end_date,leave_type,status,reviewed_by,reviewed_at) VALUES(1,'2025-01-21','2025-01-22','ANNUAL','APPROVED',1,now()); RAISE EXCEPTION 'FAIL: overlapping leave accepted';
  EXCEPTION WHEN exclusion_violation OR raise_exception THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; RAISE NOTICE 'PASS: overlapping approved leave rejected'; END;
  BEGIN INSERT INTO attendance(employee_id,work_date,status) VALUES(1,current_date+1,'PRESENT'); RAISE EXCEPTION 'FAIL: future attendance accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF; RAISE NOTICE 'PASS: future attendance rejected'; END;
END $$;
