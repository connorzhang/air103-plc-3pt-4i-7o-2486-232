local pt100_control = {}
local function new(opts)
local self = {}
self.CONTROL_CYCLE = (opts and opts.control_cycle_ms) or 50
self.MIN_DUTY_CYCLE = 0
self.MAX_DUTY_CYCLE = (opts and opts.max_duty) or 90
self.PRECISION_INTEGRAL_LIMIT = 50
self.Kp = (opts and opts.Kp) or 8.0
self.Ki = (opts and opts.Ki) or 0.12
self.Kd = (opts and opts.Kd) or 120
self.Kff = (opts and opts.Kff) or 3.0
self.Wd = (opts and opts.Wd) or 120
self.shutdown_factor = (opts and opts.shutdown_factor) or 1.05
self.integral = 0
self.last_error = 0
self.last_derivative = 0
self.last_temp = 0
function self.set_target(target)
self.Wd = target
end
function self.get_target()
return self.Wd
end
function self.set_params(params)
if params.Kp then self.Kp = params.Kp end
if params.Ki then self.Ki = params.Ki end
if params.Kd then self.Kd = params.Kd end
if params.Kff then self.Kff = params.Kff end
if params.shutdown_factor then self.shutdown_factor = params.shutdown_factor end
if params.max_duty then self.MAX_DUTY_CYCLE = params.max_duty end
if params.control_cycle_ms then self.CONTROL_CYCLE = params.control_cycle_ms end
end
function self.reset()
self.integral = 0
self.last_error = 0
self.last_derivative = 0
self.last_temp = 0
end
local function fuzzy_tuning(error, error_rate)
local kp_factor, ki_factor, kd_factor = 1.0, 1.0, 1.0
local abs_error = math.abs(error)
if abs_error > 2.0 then
kp_factor = 1.5
ki_factor = 0.8
kd_factor = 1.2
elseif abs_error > 1.0 then
kp_factor = 1.2
ki_factor = 1.0
kd_factor = 1.1
elseif abs_error > 0.5 then
kp_factor = 1.0
ki_factor = 1.2
kd_factor = 1.0
else
kp_factor = 0.8
ki_factor = 1.5
kd_factor = 0.9
end
local abs_error_rate = math.abs(error_rate)
if abs_error_rate > 1.0 then
kp_factor = kp_factor * 1.1
kd_factor = kd_factor * 1.3
elseif abs_error_rate < 0.1 then
ki_factor = ki_factor * 1.2
end
return self.Kp * kp_factor, self.Ki * ki_factor, self.Kd * kd_factor
end
function self.step(current_temp)
local dt = self.CONTROL_CYCLE / 1000
local shutdown_temp = self.Wd * self.shutdown_factor
if current_temp > shutdown_temp then
return self.MIN_DUTY_CYCLE, 0, 0, 0, 0, 0
end
local error = self.Wd - current_temp
local error_rate = (error - self.last_error) / dt
local fuzzy_kp, fuzzy_ki, fuzzy_kd = fuzzy_tuning(error, error_rate)
local proportional = fuzzy_kp * error
if math.abs(error) < 0.1 then
self.integral = self.integral + error * dt * fuzzy_ki * 1.5
else
self.integral = self.integral + error * dt * fuzzy_ki
end
self.integral = math.max(-self.PRECISION_INTEGRAL_LIMIT, math.min(self.PRECISION_INTEGRAL_LIMIT, self.integral))
local derivative = (error - self.last_error) / dt
derivative = derivative * 0.7 + self.last_derivative * 0.3
self.last_derivative = derivative
local derivative_term = fuzzy_kd * derivative
local feedforward = 0
if self.last_temp > 0 then
local temp_change_rate = (current_temp - self.last_temp) / dt
feedforward = temp_change_rate * self.Kff
end
local pid_output = proportional + self.integral + derivative_term + feedforward
if current_temp >= self.Wd then
if current_temp >= self.Wd + 0.3 then
pid_output = self.MIN_DUTY_CYCLE
elseif current_temp >= self.Wd + 0.1 then
pid_output = pid_output * 0.1
else
pid_output = pid_output * 0.5
end
end
local duty_cycle = math.max(self.MIN_DUTY_CYCLE, math.min(self.MAX_DUTY_CYCLE, math.floor(pid_output + 0.5)))
if error > 1.0 and duty_cycle == self.MIN_DUTY_CYCLE then
duty_cycle = 3
end
self.last_error = error
self.last_temp = current_temp
return duty_cycle, error, proportional, self.integral, derivative_term, pid_output
end
return self
end
pt100_control.new = new
return pt100_control