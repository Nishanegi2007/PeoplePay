require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');

const app = express();
app.use(cors({ origin: process.env.CLIENT_ORIGIN || 'http://localhost:5173' }));
app.use(express.json());
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const secret = process.env.JWT_SECRET;
if (!secret && process.env.NODE_ENV !== 'test') console.warn('Set JWT_SECRET in backend/.env before exposing this server.');

function auth(req, res, next) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, '');
  if (!token) return res.status(401).json({ error: 'Sign in required.' });
  try { req.user = jwt.verify(token, secret); next(); }
  catch { return res.status(401).json({ error: 'Session is invalid or expired.' }); }
}
const hr = (req, res, next) => req.user?.role === 'HR_ADMIN' ? next() : res.status(403).json({ error: 'HR/Admin access required.' });
const asyncRoute = fn => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

app.get('/api/health', asyncRoute(async (_req, res) => { await pool.query('SELECT 1'); res.json({ status: 'ok', database: 'connected' }); }));
app.post('/api/auth/login', asyncRoute(async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'Email and password are required.' });
  const { rows } = await pool.query('SELECT user_id, employee_id, email, password_hash, role FROM app_user WHERE lower(email)=lower($1) AND active=true', [email]);
  const u = rows[0];
  if (!u || !(await bcrypt.compare(password, u.password_hash))) return res.status(401).json({ error: 'Invalid email or password.' });
  const token = jwt.sign({ id: u.user_id, employeeId: u.employee_id, email: u.email, role: u.role }, secret, { expiresIn: '8h' });
  res.json({ token, user: { email: u.email, employeeId: u.employee_id, role: u.role } });
}));
app.get('/api/auth/me', auth, (req, res) => res.json({ user: req.user }));

app.get('/api/dashboard', auth, asyncRoute(async (req, res) => {
  const admin = req.user.role === 'HR_ADMIN';
  const [employees, attendance, payroll] = await Promise.all([
    pool.query('SELECT count(*)::int AS count FROM employee WHERE active=true'),
    pool.query(`SELECT count(*)::int AS count FROM attendance WHERE work_date >= date_trunc('month', current_date)::date AND work_date < (date_trunc('month',current_date)+interval '1 month')::date ${admin ? '' : 'AND employee_id=$1'}`, admin ? [] : [req.user.employeeId]),
    pool.query(`SELECT count(*)::int AS count, coalesce(sum(net_pay),0)::numeric(12,2) AS total FROM payroll WHERE period_start=date_trunc('month',current_date)::date ${admin ? '' : 'AND employee_id=$1'}`, admin ? [] : [req.user.employeeId])
  ]);
  res.json({ activeEmployees: admin ? employees.rows[0].count : 1, monthAttendance: attendance.rows[0].count, currentPayroll: payroll.rows[0] });
}));

app.get('/api/employees', auth, asyncRoute(async (req, res) => {
  if (req.user.role !== 'HR_ADMIN') {
    const { rows } = await pool.query('SELECT employee_id, first_name, last_name, department, job_title, email, hire_date, active FROM employee WHERE employee_id=$1', [req.user.employeeId]);
    return res.json(rows);
  }
  const { rows } = await pool.query('SELECT employee_id, first_name, last_name, department, job_title, email, hire_date, active FROM employee ORDER BY employee_id'); res.json(rows);
}));
app.post('/api/employees', auth, hr, asyncRoute(async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { firstName, lastName, department, jobTitle, email, hireDate, password } = req.body;
    const { rows } = await client.query('INSERT INTO employee(first_name,last_name,department,job_title,email,hire_date) VALUES($1,$2,$3,$4,$5,$6) RETURNING *', [firstName,lastName,department,jobTitle,email?.toLowerCase(),hireDate]);
    if (password) await client.query('INSERT INTO app_user(employee_id,email,password_hash,role) VALUES($1,$2,$3,\'EMPLOYEE\')',[rows[0].employee_id,email.toLowerCase(),await bcrypt.hash(password,12)]);
    await client.query('COMMIT'); res.status(201).json(rows[0]);
  } catch(err) { await client.query('ROLLBACK'); throw err; } finally { client.release(); }
}));
app.patch('/api/employees/:id', auth, hr, asyncRoute(async (req,res) => {
  const { firstName,lastName,department,jobTitle,email,hireDate,active } = req.body;
  const { rows } = await pool.query(`UPDATE employee SET first_name=coalesce($1,first_name),last_name=coalesce($2,last_name),department=coalesce($3,department),job_title=coalesce($4,job_title),email=coalesce($5,email),hire_date=coalesce($6,hire_date),active=coalesce($7,active) WHERE employee_id=$8 RETURNING *`,[firstName,lastName,department,jobTitle,email?.toLowerCase() || null,hireDate || null,active ?? null,req.params.id]);
  if(!rows.length) return res.status(404).json({error:'Employee not found.'}); res.json(rows[0]);
}));
app.get('/api/salaries', auth, hr, asyncRoute(async (_req,res) => {
  const { rows } = await pool.query('SELECT s.*,e.first_name,e.last_name FROM salary s JOIN employee e USING(employee_id) ORDER BY employee_id,effective_from DESC'); res.json(rows);
}));
app.post('/api/salaries', auth, hr, asyncRoute(async (req,res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { employeeId,effectiveFrom,baseMonthly,allowanceMonthly,taxRate } = req.body;
    await client.query(`UPDATE salary SET effective_to=$1::date-1 WHERE employee_id=$2 AND effective_to IS NULL AND effective_from<$1`,[effectiveFrom,employeeId]);
    const result = await client.query('INSERT INTO salary(employee_id,effective_from,base_monthly,allowance_monthly,tax_rate) VALUES($1,$2,$3,$4,$5) RETURNING *',[employeeId,effectiveFrom,baseMonthly,allowanceMonthly === '' || allowanceMonthly == null ? 0 : allowanceMonthly,taxRate === '' || taxRate == null ? 0.1 : taxRate]);
    await client.query('COMMIT'); res.status(201).json(result.rows[0]);
  } catch(err) { await client.query('ROLLBACK'); throw err; } finally { client.release(); }
}));

app.get('/api/attendance', auth, asyncRoute(async (req, res) => {
  const employeeId = req.user.role === 'HR_ADMIN' ? (req.query.employeeId || null) : req.user.employeeId;
  const { rows } = await pool.query(`SELECT a.*, e.first_name, e.last_name FROM attendance a JOIN employee e USING(employee_id) WHERE ($1::int IS NULL OR a.employee_id=$1) AND ($2::date IS NULL OR a.work_date >= $2) AND ($3::date IS NULL OR a.work_date <= $3) ORDER BY work_date DESC, employee_id LIMIT 500`, [employeeId,req.query.from || null,req.query.to || null]); res.json(rows);
}));
app.post('/api/attendance', auth, hr, asyncRoute(async (req, res) => {
  const employeeId = req.user.role === 'HR_ADMIN' ? Number(req.body.employeeId) : req.user.employeeId;
  const { workDate, checkIn, checkOut, status='PRESENT', notes=null } = req.body;
  const { rows } = await pool.query('INSERT INTO attendance(employee_id,work_date,check_in,check_out,status,notes) VALUES($1,$2,$3,$4,$5,$6) RETURNING *', [employeeId,workDate,checkIn || null,checkOut || null,status,notes]); res.status(201).json(rows[0]);
}));

app.get('/api/leaves', auth, asyncRoute(async (req, res) => {
  const id = req.user.role === 'HR_ADMIN' ? (req.query.employeeId || null) : req.user.employeeId;
  const { rows } = await pool.query('SELECT l.*,e.first_name,e.last_name FROM leave_request l JOIN employee e USING(employee_id) WHERE ($1::int IS NULL OR l.employee_id=$1) ORDER BY start_date DESC LIMIT 500',[id]); res.json(rows);
}));
app.post('/api/leaves', auth, hr, asyncRoute(async (req, res) => {
  const id = req.user.role === 'HR_ADMIN' ? Number(req.body.employeeId) : req.user.employeeId;
  const { startDate,endDate,leaveType,reason } = req.body;
  const { rows } = await pool.query('INSERT INTO leave_request(employee_id,start_date,end_date,leave_type,reason) VALUES($1,$2,$3,$4,$5) RETURNING *',[id,startDate,endDate,leaveType,reason || null]); res.status(201).json(rows[0]);
}));
app.patch('/api/leaves/:id', auth, hr, asyncRoute(async (req,res) => {
  const { rows } = await pool.query('UPDATE leave_request SET status=$1, reviewed_by=$2, reviewed_at=now() WHERE leave_id=$3 RETURNING *',[req.body.status,req.user.id,req.params.id]);
  if (!rows.length) return res.status(404).json({error:'Leave request not found.'}); res.json(rows[0]);
}));

app.get('/api/payroll', auth, asyncRoute(async (req,res) => {
  const id = req.user.role === 'HR_ADMIN' ? (req.query.employeeId || null) : req.user.employeeId;
  const { rows } = await pool.query('SELECT p.*,e.first_name,e.last_name FROM payroll p JOIN employee e USING(employee_id) WHERE ($1::int IS NULL OR p.employee_id=$1) ORDER BY period_start DESC,employee_id LIMIT 500',[id]); res.json(rows);
}));
app.post('/api/payroll/run', auth, hr, asyncRoute(async (req,res) => {
  const client = await pool.connect();
  try { await client.query('BEGIN'); const { rows } = await client.query('CALL generate_monthly_payroll($1,$2)',[req.body.periodStart,req.user.id]); const list = await client.query('SELECT p.*,e.first_name,e.last_name FROM payroll p JOIN employee e USING(employee_id) WHERE p.period_start=$1 ORDER BY employee_id',[req.body.periodStart]); await client.query('COMMIT'); res.json(list.rows); }
  catch (err) { await client.query('ROLLBACK'); throw err; } finally { client.release(); }
}));

app.get('/api/reports/attendance-monthly', auth, asyncRoute(async (req,res) => {
  const id = req.user.role === 'HR_ADMIN' ? (req.query.employeeId || null) : req.user.employeeId;
  const { rows } = await pool.query('SELECT * FROM monthly_attendance_summary WHERE month_start=$1 AND ($2::int IS NULL OR employee_id=$2) ORDER BY employee_id',[req.query.month,id]); res.json(rows);
}));
app.get('/api/reports/late-marks', auth, asyncRoute(async (req,res) => {
  const id = req.user.role === 'HR_ADMIN' ? (req.query.employeeId || null) : req.user.employeeId;
  const { rows } = await pool.query('SELECT a.employee_id,e.first_name,e.last_name,a.work_date,a.check_in FROM attendance a JOIN employee e USING(employee_id) WHERE a.status <> \'LEAVE\' AND a.check_in > time \'09:15\' AND ($1::int IS NULL OR a.employee_id=$1) AND ($2::date IS NULL OR a.work_date >= $2) AND ($3::date IS NULL OR a.work_date <= $3) ORDER BY a.work_date DESC',[id,req.query.from || null,req.query.to || null]); res.json(rows);
}));
app.get('/api/reports/salary-slip/:id', auth, asyncRoute(async (req,res) => {
  const id = req.user.role === 'HR_ADMIN' ? Number(req.params.id) : req.user.employeeId;
  const { rows } = await pool.query('SELECT p.*,e.first_name,e.last_name,e.department,e.job_title,e.email FROM payroll p JOIN employee e USING(employee_id) WHERE p.employee_id=$1 AND p.period_start=$2',[id,req.query.month]); if (!rows.length) return res.status(404).json({error:'Salary slip not found.'}); res.json(rows[0]);
}));

app.use((err, _req, res, _next) => {
  console.error(err);
  if (err.code === '23505') return res.status(409).json({error:'That record already exists.'});
  if (err.code === '23514' || err.code === '23P01') return res.status(400).json({error:err.message});
  if (err.code === '23503') return res.status(400).json({error:'Referenced employee or user does not exist.'});
  res.status(500).json({error: process.env.NODE_ENV === 'production' ? 'Internal server error.' : err.message});
});
if (require.main === module) app.listen(process.env.PORT || 5000, () => console.log(`Payroll API listening on port ${process.env.PORT || 5000}`));
module.exports = { app, pool, auth, hr };
