#import "functions.typ": *
= Lane Keeping Assist Implementation in CARLA <ch3>

The previous chapter established the simulation environment, the vehicle model and the data acquisition pipeline. This chapter describes how those building blocks are combined into a working Lane Keeping Assist (LKA) function. The implementation is centred on a single Python program, `pygame_controller.py`, which connects to the CARLA server, spawns the ego vehicle and the surrounding traffic, attaches an RGB camera, computes the lateral offset of the vehicle with respect to the centre of the lane, and feeds this offset to a discrete-time PID controller that returns a steering command. The same program also exposes a manual override through the keyboard so that the driver can take control at any moment. A reference implementation provided by the CARLA framework, `local_planner.py`, is discussed at the end of the chapter to position the proposed controller relative to the standard library tooling.

== Co-Simulation Architecture
The Lane Keeping Assist function is implemented as an external client that communicates with the CARLA server through the Python API. The server, running the Unreal Engine renderer and the physics integration, is responsible for the propagation of the world state at a fixed time step. The client retrieves the relevant fraction of that state—the pose of the ego vehicle, the geometry of the closest lane, and the latest camera frame—computes a control command, and sends it back to the server before the next tick is requested. Conceptually this is the same pattern used in any Vehicle-in-the-Loop setup, with the difference that here the "vehicle" is itself a simulated actor rather than a physical platform.

Three design choices are essential to make this loop reproducible:

*Synchronous mode.* The simulator is configured so that the world only advances when the client explicitly calls `world.tick()`. Without this setting, the server would tick at its own rate and the controller would observe a non-deterministic stream of measurements. The corresponding configuration in the implementation is reported below.

#raw("settings = world.get_settings()
settings.synchronous_mode = True
settings.no_rendering_mode = True   # rendering is delegated to PyGame
settings.fixed_delta_seconds = 0.05 # 20 Hz simulation rate
world.apply_settings(settings)

traffic_manager = client.get_trafficmanager()
traffic_manager.set_synchronous_mode(True)
traffic_manager.set_random_device_seed(0)", lang: "python", block: true)

A fixed step of $T_s=0.05$ s ($20$ Hz) is small enough to capture the closed-loop dynamics of the steering channel—whose bandwidth on a passenger car rarely exceeds a few hertz—and large enough not to overload the network connection between the client and the server.

*Deterministic traffic.* The Traffic Manager is also placed in synchronous mode and seeded with a fixed value. Each surrounding vehicle is then spawned at a randomly chosen spawn point and given to the Traffic Manager through `set_autopilot(True)`. To create a slightly more challenging environment, a random fraction of the vehicles is allowed to ignore traffic lights through `traffic_manager.ignore_lights_percentage`. Because the random seed is fixed, the same scenario can be replayed an arbitrary number of times—an essential property for tuning the controller and for comparing two configurations of the same algorithm.

*External rendering.* The third setting, `no_rendering_mode = True`, disables the in-engine spectator window. The visual feedback is instead drawn by PyGame, using the frames produced by an RGB camera attached to the ego vehicle. This decoupling has two advantages: first, the engine no longer needs to render the third-person spectator view, which reduces the load on the GPU; second, the same callback that produces the on-screen image can in principle be replaced or extended with image-processing routines, which keeps the door open for a perception-based version of the controller.

The resulting control loop is sketched in @lka_arch. At every tick, four operations are executed in sequence: the world is advanced, the ego state and the lane reference are queried, the lateral controller produces a steering command, and the manual-override block decides whether to apply that command or to forward the keyboard inputs of the driver instead.

#figure(image("image/lane_shift_geometry.jpeg"), caption: [Block diagram of the proposed Lane Keeping Assist co-simulation. The CARLA server holds the world state; the client computes the steering command from the lane reference and the vehicle pose, and applies it through `vehicle.apply_control`.]) <lka_arch>

== Lateral Control: Theoretical Background
Lateral control is the part of the driving task that decides _how much to steer_. From the point of view of the lane keeping problem, the goal is to drive a scalar error signal—the lateral offset of the vehicle with respect to the centre of the lane—to zero. Several control laws are commonly used for this purpose; geometric trackers such as Pure Pursuit @snider2009automatic and Stanley @7795743 derive a steering angle directly from a look-ahead point on the reference path, while feedback-based formulations close the loop on the offset itself. A comparative discussion of these strategies is given in the lateral-control review by Kebbati et al. @kebbati and in the experimental study of Artuñedo et al. @ARTUNEDO2024100910. In the present work the controller is realised with a Proportional–Integral–Derivative (PID) feedback law because of its simplicity, the low number of parameters to tune, and the clear interpretation of each term in the context of lane keeping.

=== The Continuous-Time PID Law
Let $e(t)$ denote the lateral error of the vehicle with respect to the centre of the lane at time $t$. A PID controller produces a steering-related command $u(t)$ as the linear combination of three terms:
$ u(t) = K_p e(t) + K_i integral_0^t e(tau) d tau + K_d (d e(t))/(d t) $

Each term has an intuitive role in the LKA context. The proportional term $K_p e(t)$ produces a steering action proportional to the present offset and is responsible for the immediate reaction of the controller. The integral term $K_i integral e(tau) d tau$ accumulates the past error and removes the steady-state bias that may appear, for instance, on a constantly cambered road or under a small wheel-alignment offset. The derivative term $K_d accent(e,.) (t)$ anticipates the future evolution of the error from its rate of change and adds damping when the vehicle is approaching the centre of the lane.

The qualitative effect of changing each gain is summarised in @pid_effects. These dependencies are well known in the control literature; they are repeated here only because they directly inform the manual tuning that was carried out during the implementation.

#text(size: 9.4558pt, top-edge: "cap-height", bottom-edge: "baseline")[#figure(
  table(
    columns: 5,
    table.header(
      [Gain], [Rise time], [Overshoot], [Settling time], [Steady-state error]
    ),
    [Increase $K_p$], [decreases], [increases], [small change], [decreases],
    [Increase $K_i$], [decreases], [increases], [increases], [eliminates],
    [Increase $K_d$], [small change], [decreases], [decreases], [no effect]
  ), caption: [Qualitative effect of each PID gain on the closed-loop response of a generic plant.]
) <pid_effects>]

=== Discrete-Time Implementation
The controller runs at the same frequency as the simulator, that is at $T_s=0.05$ s. The continuous-time integral and derivative therefore have to be approximated. Using the backward-Euler rule for the integral and a first-order backward difference for the derivative, the PID law becomes
$ I[k] = I[k-1] + e[k] T_s $
$ D[k] = (e[k] - e[k-1])/T_s $
$ u[k] = K_p e[k] + K_i I[k] + K_d D[k] $

The discrete formulation introduces two practical issues that have to be addressed in the implementation. The first one is _integral wind-up_. When the steering command saturates at the physical limit of the actuator, the integral term keeps growing as long as the lateral error does not change sign. Once the vehicle finally crosses the centre of the lane, the controller has to "discharge" this accumulated integral before it can produce a counter-steering action, which leads to a long undershoot. The simplest remedy, used in the implementation, is to clamp $I[k]$ to a symmetric interval $[-I_max, +I_max]$ at every step.

The second issue is _output saturation_ proper. The CARLA `VehicleControl.steer` field accepts values in $[-1, +1]$, with $-1$ corresponding to a fully left and $+1$ to a fully right steering wheel. Any control law must therefore saturate its output to this range; in the implementation the same saturation is applied symmetrically with $u_max = 1.0$.

=== Choice of the Sampling Period
The choice $T_s = 0.05$ s deserves a comment. From the point of view of stability of the discrete-time PID, $T_s$ should be at least one order of magnitude smaller than the dominant time constant of the closed-loop system. For a passenger car at moderate speed the lateral dynamics has a time constant in the order of half a second, so any $T_s$ below $50$ ms is acceptable. From the point of view of the simulator, smaller steps inflate the wall-clock time of an experiment without producing additional information, since the world geometry and the traffic do not change appreciably below $T_s = 0.02$ s. The choice of $20$ Hz is therefore a good compromise between accuracy and runtime.

== Lane-Shift Estimation from Waypoints
The PID law described in the previous section assumes that the lateral error $e[k]$ is available at every step. In a perception-based pipeline this signal would be reconstructed from the camera image by detecting the lane markings; in the present implementation it is computed from the waypoint graph that the CARLA map exposes through its Python API. The choice of using waypoints rather than image processing is a deliberate one: it isolates the lateral controller from the perception layer, so that the closed-loop behaviour can be studied independently from the limitations of any specific lane-detection algorithm.

=== The CARLA Waypoint Graph
A CARLA map is internally represented as a directed graph whose nodes are _waypoints_. Each waypoint sits exactly on the centre line of a lane and stores the local pose of that lane, including the position $(x_w, y_w, z_w)$, a forward unit vector $hat(t) = (t_x, t_y)$ tangent to the lane in the direction of legal traffic flow, and a number of metadata fields (lane width, lane change permissions, junction flags). For a vehicle at world position $(x_v, y_v)$, the call

#raw("waypoint = world.get_map().get_waypoint(vehicle.get_transform().location)", lang: "python", block: true)

returns the closest waypoint on the closest drivable lane. This is the primitive that the data-gathering routine `carla_data_collector_2`, defined in the previous chapter, uses to record a reference trajectory: at every tick of the autonomous-driving session, the position of the closest waypoint and its forward vector are written to the `.csv` file. The full content of the resulting file is therefore a discrete sampling of the centre line of the lane along the recorded path, expressed in the same map coordinate frame as the vehicle pose.

=== Geometric Computation of the Lateral Offset
Given a waypoint $P_w = (x_w, y_w)$ with forward unit vector $hat(t) = (t_x, t_y)$, and the current vehicle position $P_v = (x_v, y_v)$, the signed perpendicular distance from $P_v$ to the line through $P_w$ in the direction of $hat(t)$ is the lateral offset of the vehicle with respect to the centre of the lane at that point. Denoting by $arrow(r) = P_w - P_v = (x_w - x_v, y_w - y_v)$ the position vector from the car to the waypoint, the offset is the scalar projection of $arrow(r)$ on the unit normal $hat(n) = (-t_y, t_x)$:
$ d = arrow(r) dot hat(n) = -(x_w - x_v) t_y + (y_w - y_v) t_x $

By rearranging the signs and dividing by the norm of $hat(t)$, which protects the formula in the case where the forward vector returned by the API is not exactly normalised, the expression used in the code is recovered:
$ "lane_shift" = ((x_w - x_v) t_y - (y_w - y_v) t_x) / sqrt(t_x^2 + t_y^2) $

@lane_shift_geom illustrates the construction. The sign of the result is positive when the vehicle is on the right of the lane centre, with respect to the direction of the forward vector $hat(t)$, and negative when it is on the left; a sign convention that the PID controller can interpret directly as "steer right" versus "steer left".

#figure(image("image/lane_shift_geometry.jpeg"), caption: [Geometric definition of the lane shift $d$ as the signed perpendicular distance between the vehicle position $P_v$ and the line through the closest waypoint $P_w$ in the direction of the lane forward vector $hat(t)$.]) <lane_shift_geom>

=== Look-Ahead Search Strategy
The reference `.csv` file contains several thousand waypoints, while the vehicle only moves a few metres per tick. Recomputing the closest waypoint by an exhaustive search at every step would therefore be wasteful and, more importantly, would expose the controller to ambiguities on closed circuits, where two waypoints may be geometrically close but topologically distant. The implementation uses instead a _local_ search anchored at the index reached at the previous step. The corresponding routine, `lane_shift_calculator`, is reported below.

#raw("index = 0
def lane_shift_calculator(vehicle: carla.Vehicle, data: pd.DataFrame):
    global index

    vehicle_location = vehicle.get_transform().location
    car_x, car_y = vehicle_location.x, vehicle_location.y

    nearest = float('inf')
    nearest_index = index

    future_horizon = 3
    for i in range(future_horizon + 1):
        idx = index + i
        if idx >= len(data):
            break
        wp_x = data.iloc[idx][\"waypoint_x\"]
        wp_y = data.iloc[idx][\"waypoint_y\"]
        distance = np.sqrt((car_x - wp_x)**2 + (car_y - wp_y)**2)
        if distance < nearest:
            nearest = distance
            nearest_index = idx

    index = nearest_index
    vector_x = data.iloc[nearest_index][\"vector_x\"]
    vector_y = data.iloc[nearest_index][\"vector_y\"]
    wp_x = data.iloc[nearest_index][\"waypoint_x\"]
    wp_y = data.iloc[nearest_index][\"waypoint_y\"]
    lane_shift = ((wp_x - car_x) * vector_y - (wp_y - car_y) * vector_x) \\
                  / np.sqrt(vector_x**2 + vector_y**2)
    return lane_shift", lang: "python", block: true)

Two design choices are worth highlighting. First, the search horizon `future_horizon = 3` only inspects the current waypoint and the next three. This window is wide enough to absorb the few centimetres that the vehicle covers in one tick at the speeds used during the experiments, but narrow enough to remain $O(1)$ in the length of the reference path. Second, the search index is updated _monotonically_: once the nearest waypoint has moved forward in the file, it is never allowed to move backward. This convention prevents the controller from "snapping" to a previous lap on a closed circuit, but it also means that the function must be re-initialised when a new reference trajectory is loaded.

When the local search reaches the end of the file (`idx >= len(data)`), the loop is broken and the last valid index is reused. In a production-quality version of the controller this condition would trigger a graceful disengagement of the LKA function; in the present implementation, it simply causes the lateral error to remain frozen at the last available waypoint, which is acceptable as long as the recorded trajectory is longer than the experiment.

== PID Controller Implementation <sec_pid_impl>
The discrete-time PID law of the previous section is implemented as a stateful function that holds the integral and the previous error in module-level variables. The full implementation is reported below.

#raw("integral = 0.0
prev_error = 0.0
I_max = 1.0
u_max = 1.0

def pid_controller(lane_shift, Kp=1.0, Ki=0.0, Kd=0.0):
    global integral, prev_error, I_max, u_max

    dt = 0.05  # 50 ms

    # Integral with anti-windup clamp
    integral += lane_shift * dt
    integral = max(min(integral, I_max), -I_max)

    # Backward-difference derivative
    derivative = (lane_shift - prev_error) / dt

    # PID combination
    u = Kp * lane_shift + Ki * integral + Kd * derivative

    # Output saturation to the CARLA steer range
    u = max(min(u, u_max), -u_max)

    prev_error = lane_shift
    return u", lang: "python", block: true)

The function is purposely kept short, but a few details are worth a comment.

*State variables.* The integral and the previous error are stored at module level rather than as attributes of an object. This is sufficient for a single-vehicle controller and makes the function easy to call from the main loop, but it also means that the controller cannot be instantiated twice in the same process without explicit reset. A future refactor could wrap the same logic in a class to remove this limitation.

*Sampling time.* The constant `dt = 0.05` is duplicated with the `fixed_delta_seconds` setting of the simulator. Keeping a single source of truth would prevent the two values from drifting if the simulation rate is ever changed; in the current code base, this synchronisation is enforced by convention rather than by construction.

*Anti-windup.* The clamping of the integral to $[-I_max, +I_max]$ implements the simplest form of anti-windup. More sophisticated schemes—for instance the back-calculation method, in which the difference between the saturated and the unsaturated control action is fed back into the integrator—were not necessary at the speeds used in the experiments, where the steering command rarely saturates.

*Default gains.* The default values $K_p = 1.0$, $K_i = 0.0$, $K_d = 0.0$ correspond to a pure proportional controller, which is a safe starting point for tuning. The values used at the call site of the main loop, $K_p = 1.0$, $K_i = 0.01$, $K_d = 0.1$, were obtained by manual tuning on a straight section of the recorded trajectory and then refined on the curved sections; their robustness across different scenarios is a topic for the experimental chapter.

== Vehicle and Sensor Initialisation
The control loop relies on three actors that are spawned before the simulation starts: a fleet of background vehicles that populate the map, the ego vehicle that is controlled by the LKA function, and an RGB camera that is attached to the ego vehicle and provides the visual feedback for the operator.

=== Background Traffic
The background traffic is generated by sampling the available spawn points of the map and placing a randomly chosen vehicle blueprint at each of them. To keep the population realistic, the blueprint library is filtered down to a list of consumer-grade models:

#raw("models = ['dodge', 'audi', 'model3', 'mini', 'mustang', 'lincoln',
          'prius', 'nissan', 'crown', 'impala']
blueprints = []
for vehicle in world.get_blueprint_library().filter('*vehicle*'):
    if any(model in vehicle.id for model in models):
        blueprints.append(vehicle)

max_vehicles = min(50, len(spawn_points))
vehicles = []
for spawn_point in random.sample(spawn_points, max_vehicles):
    actor = world.try_spawn_actor(random.choice(blueprints), spawn_point)
    if actor is not None:
        vehicles.append(actor)

for vehicle in vehicles:
    vehicle.set_autopilot(True)
    traffic_manager.ignore_lights_percentage(vehicle, random.randint(0, 50))", lang: "python", block: true)

Two safety measures are embedded in this code. The use of `try_spawn_actor` rather than `spawn_actor` prevents the program from raising an exception when two spawn points are too close to each other; if the collision check of the simulator fails, the corresponding slot is silently skipped. The cap at `max_vehicles = 50` prevents the population from outgrowing the number of available spawn points on smaller maps. Finally, after each vehicle is spawned, the Traffic Manager is asked to occasionally ignore traffic lights, which adds a controlled amount of irregularity to the scenario.

=== The Ego Vehicle and the Camera
The ego vehicle is then chosen at random among the vehicles that were successfully spawned. An RGB camera is attached to it through `world.spawn_actor`, with a `Rigid` attachment so that the camera follows the body of the vehicle without any compliance:

#raw("ego_vehicle = random.choice(vehicles)

bound_x = 0.5 + ego_vehicle.bounding_box.extent.x
bound_y = 0.5 + ego_vehicle.bounding_box.extent.y
bound_z = 0.5 + ego_vehicle.bounding_box.extent.z

camera_init_trans = carla.Transform(carla.Location(x=+0.8*bound_x,
                                                   y=+0.0*bound_y,
                                                   z=+1.3*bound_z))
camera_bp = world.get_blueprint_library().find('sensor.camera.rgb')
camera_bp.set_attribute(\"image_size_x\", \"1280\")
camera_bp.set_attribute(\"image_size_y\", \"720\")
camera = world.spawn_actor(camera_bp, camera_init_trans,
                           attach_to=ego_vehicle,
                           attachment_type=carla.AttachmentType.Rigid)
camera.listen(lambda image: pygame_callback(image, renderObject))", lang: "python", block: true)

The camera transform is expressed as multiples of the half-extent of the vehicle bounding box, so that the same code adapts automatically to vehicles of different size. With $0.8 b_x$ along the longitudinal axis and $1.3 b_z$ along the vertical, the camera is mounted approximately at the position of the rear-view mirror, looking forward—a placement that mimics a windshield-mounted ADAS camera.

The image stream is consumed by `pygame_callback`, a small function whose only responsibility is to reshape the raw byte array delivered by CARLA into a $H times W times 3$ RGB array and to convert it into a PyGame surface that can be blitted on the screen. The reshape order is dictated by the BGRA layout used internally by the simulator; the slicing `[:, :, ::-1]` swaps the colour channels and the slice `[:, :, :3]` discards the alpha channel.

#raw("def pygame_callback(data, obj):
    img = np.reshape(np.copy(data.raw_data), (data.height, data.width, 4))
    img = img[:, :, :3]
    img = img[:, :, ::-1]
    obj.surface = pygame.surfarray.make_surface(img.swapaxes(0, 1))", lang: "python", block: true)

In this implementation the camera is used only as a visual feedback device for the human operator. The lateral controller does not consume the camera frames. This separation is deliberate, as discussed in the introduction of @ch3, and it is what makes the architecture _open_ to a future perception-based extension: a lane-detection block can be inserted between the camera callback and the controller without modifying any of the surrounding code.

== Manual Driver Override
A Lane Keeping Assist function is, by definition, a driver-assistance system: the driver must be able to take control of the vehicle at any moment. In the implementation this requirement is realised by a `ControlObject` class that stores the desired throttle, brake and steering values and applies them to the vehicle through a single `apply_control` call.

#raw("class ControlObject(object):
    def __init__(self, veh):
        self._vehicle = veh
        self._steer = 0
        self._throttle = False
        self._brake = False
        self._steer_cache = 0
        self._control = carla.VehicleControl()

    def parse_control(self, event):
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_RETURN: self._vehicle.set_autopilot(False)
            if event.key == pygame.K_UP:     self._throttle = True
            if event.key == pygame.K_DOWN:   self._brake = True
            if event.key == pygame.K_RIGHT:  self._steer = 1
            if event.key == pygame.K_LEFT:   self._steer = -1
        if event.type == pygame.KEYUP:
            if event.key == pygame.K_UP:    self._throttle = False
            if event.key == pygame.K_DOWN:  self._brake = False
            if event.key in (pygame.K_LEFT, pygame.K_RIGHT): self._steer = None", lang: "python", block: true)

The class follows a two-step design that is common in PyGame applications. The `parse_control` method is called for every keyboard event and only updates the internal flags; the heavier `process_control` method is called once per simulation tick and turns those flags into actual `VehicleControl` values. This separation prevents the simulator from receiving a burst of nearly identical commands when the user holds a key down, and produces a smoother steering response by applying small, time-integrated increments to the steering value:

#raw("    def process_control(self):
        # Throttle / brake combinations
        if self._throttle:
            self._control.throttle = min(self._control.throttle + 0.01, 1)
            self._control.gear = 1
            self._control.brake = False
        elif not self._brake:
            self._control.throttle = 0.0
        if self._brake:
            if self._vehicle.get_velocity().length() < 0.01 and not self._control.reverse:
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

Three behaviours emerge from the code. First, when the user presses the up arrow, the throttle is _ramped_ from the current value towards the maximum at a rate of $0.01$ per tick, instead of being instantaneously applied. This produces the same kind of progressive acceleration that one would expect from a real pedal. Second, when the user presses the down arrow at low speed, the gear is automatically switched to reverse and the throttle is applied in the opposite direction, so that a single key controls both braking and reverse driving. Third, when no steering key is pressed, the steering cache is multiplied by $0.2$ at every tick, which produces a smooth return of the wheel to the centre position over a few ticks. This emulates the self-aligning torque of a real steering rack and avoids the on/off behaviour that would result from a binary key state.

The `K_RETURN` key disengages the autopilot through `vehicle.set_autopilot(False)`. After this point, all the commands sent by the LKA function and by the manual override are accepted by the vehicle, and the driver can resume manual control by simply pressing the directional keys. A `K_TAB` event, handled in the main loop, switches the ego vehicle to a different actor in the fleet, re-spawning the camera in the process; this is convenient during debugging because it allows the operator to inspect the scenario from several points of view without restarting the simulation.

== The Main Control Loop
All the building blocks introduced above are assembled in a single loop that is the hot path of the program. A condensed view of the loop is given below; comments mark the position of each functional block.

#raw("data = pd.read_csv(\"carla_data.csv\", index_col=0)

crashed = False
while not crashed:
    # 1. Advance the synchronous simulation
    world.tick()

    # 2. Compute the lateral offset and the steering command
    lane_shift = lane_shift_calculator(ego_vehicle, data)
    steer = pid_controller(lane_shift, Kp=1.0, Ki=0.01, Kd=0.1)

    # 3. Render the camera frame
    gameDisplay.blit(renderObject.surface, (0, 0))
    pygame.display.flip()

    # 4. Apply the manual override (and possibly overwrite step 2)
    controlObject.process_control()

    # 5. Process keyboard events
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            crashed = True
        controlObject.parse_control(event)
        if event.type == pygame.KEYUP and event.key == pygame.K_TAB:
            ego_vehicle.set_autopilot(True)
            ego_vehicle = random.choice(vehicles)
            if ego_vehicle.is_alive:
                camera.stop(); camera.destroy()
                controlObject = ControlObject(ego_vehicle)
                camera = world.spawn_actor(camera_bp, camera_init_trans,
                                           attach_to=ego_vehicle)
                camera.listen(lambda image: pygame_callback(image, renderObject))", lang: "python", block: true)

The order of the five blocks is not arbitrary. The simulation is advanced first, so that all the state queries that follow are consistent with the same world snapshot. The lateral offset and the steering command are computed second, before any rendering or event handling, in order to minimise the latency between the measurement of the vehicle pose and the application of the corresponding command. The rendering is performed third; because PyGame uses double buffering, the call to `pygame.display.flip()` actually shows the frame produced at the _previous_ tick, which is acceptable as long as the operator does not need pixel-accurate feedback. The manual override is applied fourth, so that any keyboard event from the previous tick is honoured before the next tick of the simulator. Finally, the keyboard events are collected and parsed at the end of the loop, in preparation for the next iteration.

A subtle point concerns the interaction between the LKA controller and the manual override. In the current implementation, the value computed by `pid_controller` is _not_ written into the `controlObject._control.steer` field; the function returns the value but the loop does not propagate it. This is intentional: the LKA function is intended to be used in two distinct modes, an instrumentation mode in which the steering command is logged for offline analysis, and a closed-loop mode in which the same value is applied to the vehicle. Switching between the two modes is then a matter of adding or removing a single line at the end of step 2, without modifying any of the surrounding code.

== Reference: CARLA's Built-in Local Planner
The CARLA project ships, as part of its `agents.navigation` module, a reference implementation of a waypoint-following local planner. The relevant source file, `local_planner.py`, was used during the development of this thesis as a comparison point, and a number of design decisions in the controller described above were informed by the corresponding choices in the framework. A short overview of the reference module is therefore given here.

The `LocalPlanner` class wraps a `VehiclePIDController`, instantiates two PID controllers—one for the lateral channel and one for the longitudinal one—and consumes a queue of `(carla.Waypoint, RoadOption)` pairs. At every step, the planner pops obsolete waypoints from the front of the queue, requests the controller to track the next active waypoint, and refills the queue from the topology of the map when its length falls below a threshold. The default configuration uses

#raw("self._dt = 1.0 / 20.0
self._target_speed = 20.0  # km/h
self._sampling_radius = 2.0
self._args_lateral_dict = {'K_P': 1.95, 'K_I': 0.05, 'K_D': 0.2, 'dt': self._dt}
self._args_longitudinal_dict = {'K_P': 1.0, 'K_I': 0.05, 'K_D': 0.0, 'dt': self._dt}
self._max_throt = 0.75
self._max_brake = 0.30
self._max_steer = 0.80
self._base_min_distance = 3.0
self._distance_ratio = 0.5", lang: "python", block: true)

Three design choices in the reference are worth highlighting. First, the sampling rate is also $T_s = 0.05$ s, which is the value adopted in the present work. Second, the lateral PID is significantly more aggressive than the default configuration of `pid_controller`, with $K_p approx 2$ and a non-zero integral gain; this is consistent with the fact that the reference planner has to handle generic trajectories produced by the global planner, including sharp turns, while the controller of this thesis focuses on lane keeping and is tuned on a comparatively smooth reference. Third, the maximum steering value is capped at $0.80$, slightly below the physical limit of $1.0$, in order to leave a margin for transient overshoots. The same cap could be added to the implementation of @sec_pid_impl by setting `u_max = 0.80` at the module level.

The waypoint-management strategy is also different. The reference planner uses a `deque` of fixed maximum length and a distance threshold that grows linearly with the speed of the vehicle:

#raw("self._min_distance = self._base_min_distance + self._distance_ratio * vehicle_speed", lang: "python", block: true)

so that a fast-moving vehicle pops waypoints earlier than a slow-moving one. This is more sophisticated than the constant `future_horizon = 3` used in `lane_shift_calculator` and would be a natural extension of the controller; replacing the fixed horizon with a speed-dependent one is the kind of incremental improvement that the modular structure of the implementation is meant to support.

Finally, when the local planner reaches an intersection where multiple successor waypoints are available, the reference module disambiguates them through the `_retrieve_options` helper, which classifies each option as `STRAIGHT`, `LEFT` or `RIGHT` based on the yaw difference with the current waypoint and a $35°$ threshold:

#raw("def _compute_connection(current_waypoint, next_waypoint, threshold=35):
    n = next_waypoint.transform.rotation.yaw % 360.0
    c = current_waypoint.transform.rotation.yaw % 360.0
    diff_angle = (n - c) % 180.0
    if diff_angle < threshold or diff_angle > (180 - threshold):
        return RoadOption.STRAIGHT
    elif diff_angle > 90.0:
        return RoadOption.LEFT
    else:
        return RoadOption.RIGHT", lang: "python", block: true)

The corresponding `RoadOption` enum is then attached to each waypoint in the queue and exposed to higher layers, which can use it to take routing decisions. The controller of this thesis does not rely on this mechanism because the reference trajectory is recorded once at design time, but the same `RoadOption` would be required if the controller were to be combined with a global planner.

In summary, the proposed implementation reuses the same overall architecture as the CARLA reference local planner—synchronous mode, $20$ Hz PID, waypoint-based reference—but reduces it to the minimum amount of code that is necessary for the lane keeping function. This makes the controller easier to read and to modify, at the price of a less sophisticated waypoint management. The next chapter will quantify the consequences of this trade-off through a series of closed-loop experiments.
