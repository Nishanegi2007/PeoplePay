CREATE EXTENSION IF NOT EXISTS pgcrypto;
INSERT INTO employee(first_name,last_name,department,job_title,email,hire_date) VALUES
('Aarav','Sharma','Engineering','Software Engineer','aarav.sharma@example.com','2022-01-10'),
('Diya','Patel','Human Resources','HR Specialist','diya.patel@example.com','2021-06-14'),
('Ishaan','Rao','Finance','Accountant','ishaan.rao@example.com','2020-09-01'),
('Ananya','Gupta','Sales','Sales Executive','ananya.gupta@example.com','2023-02-20'),
('Kabir','Nair','Engineering','QA Engineer','kabir.nair@example.com','2022-11-07'),
('Meera','Iyer','Marketing','Marketing Analyst','meera.iyer@example.com','2021-04-19'),
('Vivaan','Singh','Operations','Operations Associate','vivaan.singh@example.com','2024-01-08'),
('Sara','Khan','Finance','Payroll Analyst','sara.khan@example.com','2019-07-23'),
('Arjun','Das','Sales','Account Manager','arjun.das@example.com','2020-03-16'),
('Nisha','Reddy','Customer Success','Support Specialist','nisha.reddy@example.com','2023-08-02');
INSERT INTO app_user(employee_id,email,password_hash,role) VALUES
(NULL,'admin@payroll.local',crypt('Admin123!',gen_salt('bf')),'HR_ADMIN'),
(1,'aarav.sharma@example.com',crypt('Employee123!',gen_salt('bf')),'EMPLOYEE'),
(2,'diya.patel@example.com',crypt('Employee123!',gen_salt('bf')),'EMPLOYEE'),
(3,'ishaan.rao@example.com',crypt('Employee123!',gen_salt('bf')),'EMPLOYEE');
INSERT INTO salary(employee_id,effective_from,base_monthly,allowance_monthly,tax_rate) VALUES
(1,'2024-01-01',85000,5000,.10),(2,'2024-01-01',72000,4500,.10),(3,'2024-01-01',78000,4000,.12),
(4,'2024-01-01',65000,6000,.10),(5,'2024-01-01',70000,3500,.10),(6,'2024-01-01',68000,5000,.10),
(7,'2024-01-01',52000,3000,.08),(8,'2024-01-01',80000,4500,.12),(9,'2024-01-01',76000,6000,.10),(10,'2024-01-01',50000,2500,.08);
-- Weekdays across January–March 2025; deterministic absences and late arrivals.
INSERT INTO attendance(employee_id,work_date,check_in,check_out,status,notes)
SELECT e.employee_id,d::date,
  CASE WHEN extract(day from d)::int % 13=0 THEN time '09:28' ELSE time '09:00' + make_interval(mins => (e.employee_id*3 % 12)) END,
  time '17:30','PRESENT',NULL
FROM employee e CROSS JOIN generate_series('2025-01-01'::date,'2025-03-31'::date,interval '1 day') d
WHERE extract(isodow from d) < 6 AND extract(day from d)::int % 17 <> e.employee_id;
-- Replace the generated attendance for two employees with valid absence rows.
UPDATE attendance SET status='ABSENT',check_in=NULL,check_out=NULL,notes='Sample unpaid absence'
WHERE work_date='2025-02-14' AND employee_id IN (2,7);
INSERT INTO leave_request(employee_id,start_date,end_date,leave_type,reason,status,reviewed_by,reviewed_at) VALUES
(1,'2025-01-20','2025-01-21','ANNUAL','Family event','APPROVED',1,now()),
(4,'2025-02-03','2025-02-04','SICK','Medical leave','APPROVED',1,now()),
(6,'2025-03-10','2025-03-10','PERSONAL','Personal appointment','PENDING',NULL,NULL);
UPDATE attendance SET status='LEAVE',check_in=NULL,check_out=NULL WHERE (employee_id=1 AND work_date BETWEEN '2025-01-20' AND '2025-01-21') OR (employee_id=4 AND work_date BETWEEN '2025-02-03' AND '2025-02-04');
CALL generate_monthly_payroll('2025-01-01',1);
CALL generate_monthly_payroll('2025-02-01',1);
CALL generate_monthly_payroll('2025-03-01',1);
