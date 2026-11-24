const { test, after } = require('node:test');
const assert = require('node:assert/strict');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'payroll-api-test-secret';
const jwt = require('jsonwebtoken');
const { pool, auth, hr } = require('../server');

const response = () => ({ code: 200, body: null, status(code) { this.code=code; return this; }, json(body) { this.body=body; return this; } });
const employeeToken = jwt.sign({ id: 2, employeeId: 1, email: 'aarav.sharma@example.com', role: 'EMPLOYEE' }, process.env.JWT_SECRET);
const adminToken = jwt.sign({ id: 1, employeeId: null, email: 'admin@payroll.local', role: 'HR_ADMIN' }, process.env.JWT_SECRET);

test('rejects a protected request without a token', () => {
  const res=response(); let passed=false;
  auth({headers:{}},res,()=>{passed=true;});
  assert.equal(res.code,401); assert.equal(passed,false);
});

test('rejects invalid and expired tokens', () => {
  const res=response(); let passed=false;
  auth({headers:{authorization:'Bearer invalid'}},res,()=>{passed=true;});
  assert.equal(res.code,401); assert.equal(passed,false);
});

test('employee is denied HR-only write access', () => {
  const req={user:jwt.verify(employeeToken,process.env.JWT_SECRET)}; const res=response(); let passed=false;
  hr(req,res,()=>{passed=true;});
  assert.equal(res.code,403); assert.equal(passed,false);
});

test('HR/Admin role passes the HR access gate', () => {
  const req={user:jwt.verify(adminToken,process.env.JWT_SECRET)}; const res=response(); let passed=false;
  hr(req,res,()=>{passed=true;});
  assert.equal(res.code,200); assert.equal(passed,true);
});

after(async()=>pool.end());
