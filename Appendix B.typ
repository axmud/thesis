#import "functions.typ": *

= Code Excerpts <app:b>
This appendix collects the Python excerpts that support @ch2 and @ch3. The full source tree is available in the open-source repository `LaneDetCarla` @lanedetcarla; what follows is a curated selection of the routines that are referenced explicitly in the text.

== Data Collectors (Chapter 2)
The two routines used during the data-gathering phase. The first one, `carla_data_collector`, records the dynamic state of the ego vehicle; the second one, `carla_data_collector_2`, records the geometric reference exposed by the CARLA waypoint graph. Both are called once per tick from the main loop.

#raw("def carla_data_collector(vehicle: carla.Vehicle):
    frame = vehicle.get_world().get_snapshot().frame
    transform = vehicle.get_transform()
    location = transform.location
    rotation = transform.rotation
    velocity = vehicle.get_velocity()
    acceleration = vehicle.get_acceleration()
    angular_velocity = vehicle.get_angular_velocity()
    waypoint = vehicle.get_world().get_map().get_waypoint(location)

    return {
        \"frame\": frame,
        \"location\": {\"x\": location.x, \"y\": location.y, \"z\": location.z},
        \"rotation\": {\"pitch\": rotation.pitch, \"yaw\": rotation.yaw, \"roll\": rotation.roll},
        \"velocity\": {\"x\": velocity.x, \"y\": velocity.y, \"z\": velocity.z},
        \"acceleration\": {\"x\": acceleration.x, \"y\": acceleration.y, \"z\": acceleration.z},
        \"angular_velocity\": {\"x\": angular_velocity.x,
                              \"y\": angular_velocity.y,
                              \"z\": angular_velocity.z},
        \"waypoint\": {\"x\": waypoint.transform.location.x,
                       \"y\": waypoint.transform.location.y,
                       \"z\": waypoint.transform.location.z},
    }


def carla_data_collector_2(vehicle: carla.Vehicle):
    waypoint = vehicle.get_world().get_map().get_waypoint(
        vehicle.get_transform().location)
    loc = waypoint.transform.location
    fwd = waypoint.transform.get_forward_vector()
    return {\"x\": loc.x, \"y\": loc.y,
            \"vector_x\": fwd.x, \"vector_y\": fwd.y}", lang: "python", block: true)

The duplicate-suppression block that wraps `carla_data_collector_2` to avoid writing identical rows to the `.csv` file when the closest waypoint does not change between consecutive ticks:

#raw("data = {\"waypoint_x\": [], \"waypoint_y\": [],
        \"vector_x\": [],  \"vector_y\": []}

while not crashed:
    world.tick()
    sample = carla_data_collector_2(ego_vehicle)
    if (not data[\"waypoint_x\"]
        or sample[\"x\"] != data[\"waypoint_x\"][-1]
        or sample[\"y\"] != data[\"waypoint_y\"][-1]):
        data[\"waypoint_x\"].append(sample[\"x\"])
        data[\"waypoint_y\"].append(sample[\"y\"])
        data[\"vector_x\"].append(sample[\"vector_x\"])
        data[\"vector_y\"].append(sample[\"vector_y\"])

pd.DataFrame(data).to_csv(\"carla_data.csv\", index=True)", lang: "python", block: true)

The corresponding logging routine for the manual-driving mode. The autopilot is disengaged with `vehicle.set_autopilot(False)` and the user inputs from the keyboard are translated by the `ControlObject` class (also reported in this appendix) into a `carla.VehicleControl` object that is applied to the ego vehicle.

#raw("data = {
    \"frame\": [], \"x\": [], \"y\": [], \"yaw\": [],
    \"v_x\": [], \"v_y\": [], \"a_x\": [],
    \"throttle\": [], \"brake\": [], \"steer\": []
}

while not crashed:
    world.tick()
    snapshot     = world.get_snapshot()
    transform    = ego_vehicle.get_transform()
    velocity     = ego_vehicle.get_velocity()
    acceleration = ego_vehicle.get_acceleration()
    control      = ego_vehicle.get_control()

    data[\"frame\"].append(snapshot.frame)
    data[\"x\"].append(transform.location.x)
    data[\"y\"].append(transform.location.y)
    data[\"yaw\"].append(transform.rotation.yaw)
    data[\"v_x\"].append(velocity.x)
    data[\"v_y\"].append(velocity.y)
    data[\"a_x\"].append(acceleration.x)
    data[\"throttle\"].append(control.throttle)
    data[\"brake\"].append(control.brake)
    data[\"steer\"].append(control.steer)

pd.DataFrame(data).to_csv(\"manual_drive_log.csv\", index=False)", lang: "python", block: true)

== Cross-Track Error (Chapter 3, @sec_xtrack)
The vectorised implementation of @eqt:eq_lane_shift. A monotonically increasing global index is used so that the search remains $O(1)$ in the length of the reference path and so that the controller cannot "snap" backwards on a closed circuit.

#raw("index = 0
FUTURE_HORIZON = 10

def lane_shift_calculator(vehicle: carla.Vehicle):
    global index
    loc = vehicle.get_transform().location
    car_x, car_y = loc.x, loc.y

    end = min(index + FUTURE_HORIZON + 1, len(wp_x_arr))
    dx = wp_x_arr[index:end] - car_x
    dy = wp_y_arr[index:end] - car_y
    sq_dist = dx * dx + dy * dy
    offset = int(np.argmin(sq_dist))
    nearest_index = index + offset
    index = nearest_index

    vx = vec_x_arr[nearest_index]
    vy = vec_y_arr[nearest_index]
    lane_shift = dx[offset] * vy - dy[offset] * vx

    nearest_dist = float(np.sqrt(sq_dist[offset]))
    return lane_shift, nearest_dist", lang: "python", block: true)

== Heading Error and Look-Ahead Target (Chapter 3, @sec_heading)
The heading error is computed via a two-argument arctangent so that all four quadrants are handled correctly. The look-ahead target is the first waypoint on the recorded path whose distance from the vehicle exceeds $L_d(v) = L_d^"min" + k_L  v$.

#raw("LOOKAHEAD_MIN = 4.0   # m
LOOKAHEAD_K   = 0.6   # s

def get_lookahead_target(vehicle: carla.Vehicle):
    loc = vehicle.get_transform().location
    car_x, car_y = loc.x, loc.y
    v = vehicle.get_velocity()
    speed_mps = math.sqrt(v.x ** 2 + v.y ** 2)
    Ld = LOOKAHEAD_MIN + LOOKAHEAD_K * speed_mps
    Ld_sq = Ld * Ld

    for j in range(index, len(wp_x_arr)):
        ddx = wp_x_arr[j] - car_x
        ddy = wp_y_arr[j] - car_y
        if ddx * ddx + ddy * ddy >= Ld_sq:
            return float(wp_x_arr[j]), float(wp_y_arr[j]), j
    last = len(wp_x_arr) - 1
    return float(wp_x_arr[last]), float(wp_y_arr[last]), last


def heading_error(vehicle: carla.Vehicle, target_x: float, target_y: float):
    tf = vehicle.get_transform()
    fwd = tf.get_forward_vector()
    v_vec = np.array([fwd.x, fwd.y, 0.0])
    w_vec = np.array([target_x - tf.location.x,
                      target_y - tf.location.y, 0.0])
    norm = np.linalg.norm(v_vec) * np.linalg.norm(w_vec)
    if norm < 1e-6:
        return 0.0
    angle = math.acos(np.clip(np.dot(v_vec, w_vec) / norm, -1.0, 1.0))
    cross_z = v_vec[0] * w_vec[1] - v_vec[1] * w_vec[0]
    if cross_z < 0:
        angle = -angle
    return angle", lang: "python", block: true)

== PID Controllers (Chapter 3, @sec_pid_theory)
The discrete PID law of @eqt:eq_pid_disc is implemented as two stateful controllers, one for the lateral channel and one for the longitudinal channel. The state is held in a fixed-length deque, which provides an implicit anti-windup limit equal to the deque length times the sampling period. The output is then clipped to the actuator range.

#raw("class PIDLateralController:
    def __init__(self, K_P=1.95, K_I=0.05, K_D=0.2, dt=0.05):
        self._K_P, self._K_I, self._K_D, self._dt = K_P, K_I, K_D, dt
        self._e_buffer = deque(maxlen=10)

    def run_step(self, heading_err):
        self._e_buffer.append(heading_err)
        if len(self._e_buffer) >= 2:
            de = (self._e_buffer[-1] - self._e_buffer[-2]) / self._dt
            ie = sum(self._e_buffer) * self._dt
        else:
            de = 0.0
            ie = 0.0
        return float(np.clip(
            self._K_P * heading_err + self._K_D * de + self._K_I * ie,
            -1.0, 1.0))


class PIDLongitudinalController:
    def __init__(self, K_P=0.3, K_I=0.05, K_D=0.0, dt=0.05):
        self._K_P, self._K_I, self._K_D, self._dt = K_P, K_I, K_D, dt
        self._e_buffer = deque(maxlen=10)

    def run_step(self, target_speed, current_speed):
        error = target_speed - current_speed
        self._e_buffer.append(error)
        if len(self._e_buffer) >= 2:
            de = (self._e_buffer[-1] - self._e_buffer[-2]) / self._dt
            ie = sum(self._e_buffer) * self._dt
        else:
            de = 0.0
            ie = 0.0
        return float(np.clip(
            self._K_P * error + self._K_D * de + self._K_I * ie,
            -1.0, 1.0))", lang: "python", block: true)

The combined controller `VehiclePIDController` couples the two channels and returns a single `carla.VehicleControl` object per tick. The signed acceleration produced by the longitudinal controller is mapped to the throttle when positive and to the brake when negative; the steering output of the lateral controller is rate-limited to a maximum increment of $0.1$ per step before being applied.

#raw("class VehiclePIDController:
    def __init__(self, vehicle, args_lateral=None, args_longitudinal=None,
                 max_throttle=0.75, max_brake=0.3, max_steering=0.8):
        self._vehicle = vehicle
        self._max_throt = max_throttle
        self._max_brake = max_brake
        self._max_steer = max_steering
        self._lat = PIDLateralController(**args_lateral)
        self._lon = PIDLongitudinalController(**args_longitudinal)
        self.past_steering = 0.0

    def run_step_h(self, target_speed, heading_err):
        v = self._vehicle.get_velocity()
        current_speed = 3.6 * math.sqrt(v.x**2 + v.y**2 + v.z**2)
        accel = self._lon.run_step(target_speed, current_speed)
        steer = self._lat.run_step(heading_err)
        return self._build_control(accel, steer)

    def _build_control(self, acceleration, steering):
        control = carla.VehicleControl()
        if acceleration >= 0.0:
            control.throttle = min(acceleration, self._max_throt)
            control.brake = 0.0
        else:
            control.throttle = 0.0
            control.brake = min(abs(acceleration), self._max_brake)
        if steering > self.past_steering + 0.1:
            steering = self.past_steering + 0.1
        elif steering < self.past_steering - 0.1:
            steering = self.past_steering - 0.1
        steering = max(-self._max_steer, min(self._max_steer, steering))
        control.steer = steering
        self.past_steering = steering
        return control", lang: "python", block: true)

== Inverse Perspective Mapping (Chapter 3, @sec_vision)
The `pixel_to_vehicle` routine projects a list of image-plane points onto the ground plane in the body frame of the vehicle, under the pinhole-camera and flat-ground assumptions described in @sec_vision.

#raw("def pixel_to_vehicle(pixel_pts, cam_height,
                     image_width=1280, image_height=720,
                     fov_deg=90.0, cam_x_offset=0.0, max_range=40.0):
    p = np.asarray(pixel_pts, dtype=np.float64)
    u, v = p[:, 0], p[:, 1]

    fx = fy = image_width / (2.0 * np.tan(np.deg2rad(fov_deg) / 2.0))
    cx, cy = image_width / 2.0, image_height / 2.0

    below_horizon = v > cy + 1e-3
    u, v = u[below_horizon], v[below_horizon]
    if u.size == 0:
        return np.empty((0, 2))

    X_cam = cam_height * fy / (v - cy)
    Y_cam = X_cam * (u - cx) / fx

    pts = np.column_stack([X_cam + cam_x_offset, Y_cam])
    return pts[pts[:, 0] <= max_range]", lang: "python", block: true)

The polynomial fit and look-ahead-target evaluation that follow the IPM step:

#raw("def vision_target(centerline_body, Ld, x_min=0.5, x_max=20.0, deg=1):
    if centerline_body is None or centerline_body.shape[0] < 3:
        return None
    pts = centerline_body[(centerline_body[:, 0] > x_min) &
                          (centerline_body[:, 0] < x_max)]
    if pts.shape[0] < 3:
        return None
    coeffs = np.polyfit(pts[:, 0], pts[:, 1], deg=deg)
    y_at_Ld = float(np.polyval(coeffs, Ld))
    return Ld, y_at_Ld", lang: "python", block: true)

== System Identification (Chapter 3, @sec_sysid)
The two step experiments and the corresponding nonlinear least-squares fits, as implemented in `carla_sysid.py` and `pid_tuning.py`. The longitudinal model is a first-order step response; the lateral identification uses the steady-state value of the yaw rate to back out the steering gain $K_"steer"$.

#raw("def fit_longitudinal(lon_df, u_step):
    t = lon_df['t'].to_numpy()
    v = lon_df['speed_kmh'].to_numpy()

    def model(t, K, tau):
        return K * u_step * (1.0 - np.exp(-t / tau))

    K0 = v[-1] / u_step if u_step > 0 else 60.0
    idx63 = np.argmax(v >= 0.63 * v[-1])
    tau0 = max(t[idx63], 0.5)
    popt, _ = curve_fit(model, t, v, p0=[K0, tau0], maxfev=5000)
    return float(popt[0]), float(popt[1])


def fit_lateral_gain(lat_df, L, delta_cmd):
    n = len(lat_df)
    tail = lat_df.iloc[int(0.75 * n):]
    psi_dot_ss = math.radians(tail['yaw_rate_dps'].mean())
    V = tail['speed_kmh'].mean() / 3.6
    K_steer = psi_dot_ss * L / (V * delta_cmd)
    return float(K_steer), float(V), float(psi_dot_ss)", lang: "python", block: true)

The pole-placement routines that map the identified plant parameters into the analytical PID gains derived in @eqt:eq_xtrack_gains and @eqt:eq_heading_gains:

#raw("def tune_lateral_xtrack(K_lat, wn):
    # double integrator -> (s+wn)^3 -> full PID
    K_d = 3.0 * wn        / K_lat
    K_p = 3.0 * wn * wn   / K_lat
    K_i = wn * wn * wn    / K_lat
    return {'K_P': K_p, 'K_I': K_i, 'K_D': K_d}


def tune_lateral_heading(K_lat, wn, zeta=1.0):
    # single integrator -> (s+wn)^2 -> PI sufficient
    K_p = 2.0 * zeta * wn / K_lat
    K_i = wn * wn         / K_lat
    return {'K_P': K_p, 'K_I': K_i, 'K_D': 0.0}


def tune_longitudinal(K, tau, wn):
    # first-order plant -> (s+wn)^2 -> PI
    K_p = (2.0 * wn * tau - 1.0) / K
    K_i = (wn * wn * tau)        / K
    return {'K_P': K_p, 'K_I': K_i, 'K_D': 0.0}", lang: "python", block: true)

== Manual-Override Class
The `ControlObject` class implements the keyboard fallback used in all three architectures. The class follows a two-step design: the `parse_control` method is called for every keyboard event and only updates the internal flags; the heavier `process_control` method is called once per simulation tick and turns those flags into actual `VehicleControl` values, with progressive throttle ramping, automatic reverse engagement at low speed, and exponential return-to-centre on the steering wheel.

#raw("class ControlObject(object):
    def __init__(self, veh):
        self._vehicle = veh
        self._throttle = False
        self._brake = False
        self._steer = None
        self._steer_cache = 0
        self._control = carla.VehicleControl()

    def parse_control(self, event):
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_UP:    self._throttle = True
            if event.key == pygame.K_DOWN:  self._brake = True
            if event.key == pygame.K_RIGHT: self._steer = 1
            if event.key == pygame.K_LEFT:  self._steer = -1
        if event.type == pygame.KEYUP:
            if event.key == pygame.K_UP:    self._throttle = False
            if event.key == pygame.K_DOWN:
                self._brake = False
                self._control.reverse = False
            if event.key in (pygame.K_LEFT, pygame.K_RIGHT):
                self._steer = None

    def process_control(self):
        # Throttle / brake combinations
        if self._throttle:
            self._control.throttle = min(self._control.throttle + 0.01, 1)
            self._control.gear = 1
            self._control.brake = False
        elif not self._brake:
            self._control.throttle = 0.0
        if self._brake:
            if (self._vehicle.get_velocity().length() < 0.01
                    and not self._control.reverse):
                self._control.brake = 0.0
                self._control.gear = 1
                self._control.reverse = True
                self._control.throttle = min(self._control.throttle + 0.1, 1)
            elif self._control.reverse:
                self._control.throttle = min(self._control.throttle + 0.1, 1)
            else:
                self._control.throttle = 0.0
                self._control.brake = min(self._control.brake + 0.3, 1)
        else:
            self._control.brake = 0.0

        # Steering with low-pass return-to-centre
        if self._steer is not None:
            self._steer_cache += 0.03 * self._steer
            self._steer_cache = max(-0.7, min(0.7, self._steer_cache))
            self._control.steer = round(self._steer_cache, 1)
        else:
            self._steer_cache *= 0.2
            if abs(self._steer_cache) < 0.01:
                self._steer_cache = 0.0
            self._control.steer = round(self._steer_cache, 1)

        self._vehicle.apply_control(self._control)", lang: "python", block: true)
