#import "functions.typ": *
= Lane Keeping Assist: Theory, Architectures and Method Comparison <ch3>

The previous chapter established the simulation environment, the vehicle model and the data-gathering pipeline. This chapter develops the lateral-control component of the Lane Keeping Assist (LKA) function and presents three progressively richer architectures that have been implemented in the same CARLA framework. The discussion is deliberately kept theoretical: the goal of the chapter is to make explicit _why_ each design choice was made, what the corresponding plant model looks like, and what the analytical tuning procedure predicts in terms of closed-loop behaviour. Code excerpts are gathered in @app:b so that the present chapter can focus on the reasoning. The numerical evaluation of each controller in the simulator is the subject of the next chapter.

The chapter is structured as follows. @sec_lka_overview gives a high-level description of the three architectures and motivates the order in which they are introduced. @sec_bicycle revisits the kinematic bicycle model of @ch2 from the perspective of control-oriented modelling, and derives the input-output transfer function from the steering command to the lateral state of the vehicle. @sec_pid_theory recalls the PID feedback law and its discrete-time implementation, with particular attention to the issues of integral wind-up and output saturation that arise in any practical realisation. @sec_xtrack and @sec_heading then specialise the general framework to the two error signals that are most commonly used in path-following applications: the cross-track distance and the heading error to a look-ahead point. The two formulations differ only in the choice of error signal, but as it will be shown, this single choice has profound consequences on the order of the resulting plant, on the type of controller that is required for stability, and on the way the gains have to be scheduled with vehicle speed. @sec_sysid presents a systematic identification procedure that fits the parameters of the plant from open-loop step responses recorded in the simulator, and derives analytical PID gains from a pole-placement criterion. @sec_vision finally extends the heading-error formulation with a perception layer based on a deep convolutional lane-detection network and on inverse perspective mapping, which removes the dependence on a pre-recorded reference path. @sec_comparison summarises the relative merits of the three approaches from a control-theoretic standpoint.

== Overview of the Three Architectures <sec_lka_overview>
The lateral-control function has been implemented in three increasingly sophisticated forms, each of which is studied in a dedicated module of the source tree:

#list(
  [_Cross-track PID_ (`lane_shift_pid/`). The lateral error is the signed perpendicular distance between the vehicle and the closest waypoint on the recorded reference path. A discrete-time PID controller produces the steering command directly from this distance.],
  [_Heading-error PID_ (`heading_error_pid/`). The lateral error is the signed angle between the vehicle's forward direction and the line that connects the vehicle to a look-ahead point placed on the reference path at a speed-dependent distance ahead. The error signal is now an angle, and a discrete-time PI controller is sufficient to drive it to zero.],
  [_Vision-based heading-error PID_ (`detection&pid.py`). The reference path is no longer read from a pre-recorded `.csv` file. Instead, the centre line of the lane is reconstructed at every tick from the RGB camera using a deep convolutional lane-detection network and an inverse-perspective-mapping projection. A look-ahead target is selected on the reconstructed centre line and is fed to the same PI controller as in the previous case.]
)

The three architectures are sketched side by side in @three_arch. They share the same actuator (the `carla.VehicleControl.steer` field), the same simulation rate ($T_s = 0.05$ s), the same vehicle dynamics, and—crucially—the same lateral plant up to the choice of the error signal. The differences between them are confined to two well-defined components: the way the lateral error is constructed, and the structure of the PID controller that consumes it. This modular separation makes it possible to compare the three approaches on equal footing, and to attribute the observed differences in behaviour to specific design choices rather than to incidental implementation details.

#figure(image("image/three_architectures.jpeg"), caption: [Block-diagram comparison of the three lateral-control architectures investigated in this thesis. The first one closes the loop on the cross-track distance computed against a recorded path; the second one closes the loop on a heading angle derived from a speed-dependent look-ahead point; the third one replaces the recorded path with a perception pipeline that reconstructs the centre line of the lane from the camera image. All three architectures share the same actuator, the same vehicle dynamics, and the same PID structure.]) <three_arch>

== The Kinematic Bicycle Model Revisited <sec_bicycle>
The kinematic bicycle model introduced in @ch2 is the simplest description of the planar motion of a four-wheeled vehicle. It collapses the front pair of wheels into a single equivalent wheel placed at the front axle, and similarly for the rear pair, and ignores tyre slip. Under these assumptions the configuration of the vehicle is fully described by three quantities: the position $(x, y)$ of a reference point—conventionally taken at the centre of the rear axle—and the yaw angle $psi$ that the body of the vehicle makes with the world $x$-axis. The configuration space is therefore $RR^2 times S^1$, and a useful sketch of its variables is given in @bicycle.

#figure(image("image/bicycle_model.jpeg"), caption: [Kinematic bicycle model. The vehicle has wheelbase $L$, longitudinal speed $v$ at the rear axle, yaw angle $psi$ relative to the world $x$-axis, and a front steering angle $delta$ measured from the longitudinal axis of the body. The yaw rate $accent(psi, dot)$ is determined by the geometry of the model.]) <bicycle>

Two scalar control inputs act on the model: the longitudinal speed $v$ at the rear axle, controlled through the throttle and brake pedals, and the steering angle $delta$ at the front wheel. With these inputs, the equations of motion of the bicycle are
$ accent(x, dot) = v cos psi $
$ accent(y, dot) = v sin psi $
$ accent(psi, dot) = v / L tan delta $
where $L$ is the wheelbase. For the small steering angles that occur in normal driving—the LKA function is by definition active only inside the lane, so $abs(delta) < 5 degree$ in almost every situation—the small-angle approximation $tan delta approx delta$ holds with negligible error and the yaw-rate equation simplifies to
$ accent(psi, dot) = v / L delta $

In the CARLA Python API, the steering input is not the physical steering angle $delta$ but a normalised "steer command" $delta_c in [-1, +1]$ that the simulator scales internally by a vehicle-specific maximum angle $delta_max$. The relationship $delta = K_"steer" delta_c$ with $K_"steer" approx delta_max$ is approximately linear in the regime of interest @kebbati. Plugging this relationship into the yaw-rate equation gives the relation between the actuator command and the resulting yaw rate:
$ accent(psi, dot) = v K_"steer" / L  delta_c $

The key observation is that $accent(psi, dot)$ depends linearly on the steering command and on the speed. The factor $v/L$ appears because at higher speeds the same steering angle traces a larger arc per unit time. From a control-theory perspective, the steering channel of the vehicle is an _open-loop integrator_ whose gain scales with speed: if the steering command is held constant, the yaw rate is constant and the heading angle grows linearly in time. This integrator is the building block from which the two plants of @sec_xtrack and @sec_heading will be constructed.

== The PID Feedback Law <sec_pid_theory>
A Proportional–Integral–Derivative controller computes the control action $u(t)$ as a linear combination of three terms: the present error, the accumulated past error, and the rate of change of the error. Given a scalar error signal $e(t)$, the continuous-time PID law is
$ u(t) = K_p e(t) + K_i integral_0^t e(tau) d tau + K_d (d e(t))/(d t) $ <eq_pid_cont>

Each term plays a specific role in the LKA context. The proportional term $K_p e(t)$ produces an immediate reaction whose magnitude is proportional to the present error and is responsible for the fast component of the response. The integral term $K_i integral e(tau) d tau$ accumulates the past error and removes the steady-state offset that would otherwise persist when the plant has finite DC gain or when the disturbance is constant—for instance on a constantly cambered road, or under a small wheel-alignment offset. The derivative term $K_d accent(e, dot)(t)$ anticipates the future evolution of the error from its rate of change and adds damping when the error is approaching zero. The qualitative effect of changing each gain on the closed-loop response is summarised in @pid_effects; these dependencies are well known from the control literature @astrom and are repeated here only because they directly inform the manual tuning that has been performed during the development.

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
The controller runs at the same frequency as the simulator, that is at $T_s = 0.05$ s. The continuous-time integral and derivative therefore have to be approximated. Using the backward-Euler rule for the integral and a first-order backward difference for the derivative, the PID law in @eqt:eq_pid_cont becomes
$ I[k] = I[k-1] + e[k] T_s $ <eq_pid_int>
$ D[k] = (e[k] - e[k-1])/T_s $ <eq_pid_der>
$ u[k] = K_p e[k] + K_i I[k] + K_d D[k] $ <eq_pid_disc>

In the actual implementation, the integral and the derivative are not stored as scalar variables but as the running sum and the first difference of a fixed-length deque of the most recent error samples. This windowed formulation provides a built-in saturation of the integral term—the deque contains at most ten samples in the present implementation—and it makes the derivative term less sensitive to high-frequency noise on the error signal.

=== Anti-Windup and Saturation
Two practical issues must be addressed in any discrete realisation of @eqt:eq_pid_disc. The first is _integral wind-up_: when the steering command saturates at the physical limit of the actuator, the integral term keeps growing as long as the lateral error does not change sign. Once the vehicle finally crosses the centre of the lane, the controller has to "discharge" this accumulated integral before it can produce a counter-steering action, which leads to a long undershoot. The simplest remedy, used in all three architectures of the present work, is to clamp the integral to a symmetric interval $[-I_max, +I_max]$ at every step.

The second issue is _output saturation_ proper. The CARLA `VehicleControl.steer` field accepts values in $[-1, +1]$, with $-1$ corresponding to a fully left and $+1$ to a fully right steering wheel. Any control law must therefore saturate its output to this range; in the implementation, the maximum value is set to $0.8$, slightly below the physical limit, in order to leave a margin for transient overshoots—a choice that matches the default of the CARLA reference local planner @local_planner.

A third, more subtle issue is the _rate of change_ of the steering command. A PID controller is intrinsically a memoryless operator on the error sequence and can produce arbitrarily large jumps between consecutive samples, especially if the derivative term is large. Such jumps would be felt by the vehicle as a step on the steering rack and would excite high-frequency suspension dynamics. To avoid this, the steering command is rate-limited at every tick to a maximum increment of $0.1$ per step, which corresponds approximately to a $50 degree"/s"$ steering-wheel speed at the saturation level—well within the capabilities of a human driver, and well below the bandwidth at which the simulator becomes numerically unstable.

== Cross-Track Error Formulation <sec_xtrack>
The first of the three architectures closes the loop on the _cross-track error_ $e_y$, defined as the signed perpendicular distance between the vehicle and the closest waypoint on the reference path. The CARLA waypoint graph exposes, at every position of the world, the closest waypoint together with the unit forward vector $hat(t) = (t_x, t_y)$ tangent to the lane. Given the vehicle position $P_v = (x_v, y_v)$ and the closest waypoint $P_w = (x_w, y_w)$, the cross-track error is the projection of the displacement $arrow(r) = P_w - P_v$ on the unit normal $hat(n) = (-t_y, t_x)$:
$ e_y = arrow(r) dot hat(n) = (x_w - x_v) (-t_y) + (y_w - y_v) t_x $
which, after rearrangement of the signs and division by the norm of $hat(t)$ in case the forward vector returned by the API is not exactly normalised, becomes
$ e_y = ((x_w - x_v) t_y - (y_w - y_v) t_x) / sqrt(t_x^2 + t_y^2) $ <eq_lane_shift>

The geometric construction has been illustrated in @lane_shift_geom and is not repeated here.

#figure(image("image/lane_shift_geometry.jpeg"), caption: [Geometric definition of the cross-track error $e_y$ as the signed perpendicular distance between the vehicle position $P_v$ and the line through the closest waypoint $P_w$ in the direction of the lane forward vector $hat(t)$. Positive values of $e_y$ correspond to the vehicle being on the right of the lane centre with respect to the direction of travel.]) <lane_shift_geom>

=== The Cross-Track Plant
To derive the transfer function from the steering command to the cross-track error, three simple integrations have to be chained. Starting from the bicycle-model relation $accent(psi, dot) = v K_"steer" delta_c / L$ established in @sec_bicycle:

#list(
[The yaw rate $accent(psi, dot)$ integrated once gives the heading deviation $psi$ from the path tangent.],
[The heading deviation $psi$ multiplied by the vehicle speed $v$ gives the lateral velocity $accent(y, dot)$ relative to the path (small-angle approximation).],
[The lateral velocity $accent(y, dot)$ integrated once gives the cross-track distance $e_y$.]
)

In the Laplace domain, the chain of operations is
$ E_y(s) / Delta_c(s) = (v K_"steer") / L  dot  1/s  dot  v  dot  1/s  =  (v^2 K_"steer") / (L s^2) $ <eq_xtrack_plant>

The plant from the steering command to the cross-track error is therefore a _double integrator_, with a DC gain that scales with $v^2$. This is the central observation that drives every other property of the cross-track formulation. A double integrator is marginally stable on its own—it has two poles at the origin—and any feedback law that uses only the proportional and integral terms produces a closed-loop system with poles either on the imaginary axis or in the right half-plane. The derivative term is therefore _necessary_ for stability, not optional. Furthermore, the $v^2$ scaling of the DC gain means that, in order to keep the closed-loop bandwidth constant as the vehicle accelerates, all three PID gains have to be re-scaled by $1/v^2$. This is a steep dependence that will be revisited in @sec_sysid.

=== Pole Placement
A natural choice for the closed-loop denominator of a PID compensating a double integrator is a triple real pole at $s = -omega_n$, which gives a critically damped behaviour with bandwidth $omega_n$. The closed-loop characteristic polynomial of $K_p + K_i / s + K_d s$ acting on $K_"lat" / s^2$ with $K_"lat" = v^2 K_"steer" / L$ is
$ s^3 + (K_"lat" K_d) s^2 + (K_"lat" K_p) s + K_"lat" K_i $
Matching with $(s + omega_n)^3 = s^3 + 3 omega_n s^2 + 3 omega_n^2 s + omega_n^3$ yields the analytical gains
$ K_p = (3 omega_n^2)/K_"lat", quad K_i = (omega_n^3)/K_"lat", quad K_d = (3 omega_n)/K_"lat" $ <eq_xtrack_gains>

These expressions tell, at a glance, how each gain depends on the vehicle speed: $K_d$ scales as $1/v^2$ through $K_"lat"$, $K_p$ does the same, and $K_i$—the most "expensive" gain in terms of stability margin—decreases as $v^{-2}$ as well. The tuning script `pid_tuning.py` implements exactly @eqt:eq_xtrack_gains and produces, given a measurement of $K_"steer"$ from the system identification of @sec_sysid, the numerical gains that have been used in the simulator.

== Heading-Error Formulation <sec_heading>
The second architecture replaces the cross-track distance with a different scalar error signal: the angle between the vehicle's forward direction and the line connecting the vehicle to a _look-ahead point_ placed on the reference path at a speed-dependent distance $L_d$ ahead of the vehicle. This formulation is closely related to the Pure Pursuit @snider2009automatic and Stanley @7795743 geometric trackers, with the difference that here the steering command is computed by a feedback PID rather than by a fixed geometric formula. The geometric construction is illustrated in @heading_geom.

#figure(image("image/heading_error_geometry.jpeg"), caption: [Heading-error / look-ahead geometry. The look-ahead point $P_"la"$ is the closest waypoint on the reference path at distance at least $L_d$ ahead of the vehicle; the heading error $alpha$ is the signed angle between the vehicle forward unit vector $hat(f)_v$ and the line $P_v -> P_"la"$. The look-ahead distance is scheduled as $L_d = L_d^"min" + k_L  v(t)$.]) <heading_geom>

Formally, given the vehicle position $P_v = (x_v, y_v)$, its forward unit vector $hat(f)_v = (f_x, f_y)$, and the look-ahead point $P_"la" = (x_l, y_l)$, the heading error $alpha$ is computed from the dot product and the cross product of $hat(f)_v$ with the displacement $arrow(d) = P_"la" - P_v$:
$ alpha = "atan2"(hat(f)_v times arrow(d),  hat(f)_v dot arrow(d)) $
The two-argument arctangent returns a signed angle in $(-pi, +pi]$ and naturally handles all four quadrants. By convention—the same one used in the CARLA `agents.navigation.controller.PIDLateralController` and matched in the implementation—a positive $alpha$ corresponds to a target on the right of the vehicle, which calls for a positive (right) steering command.

=== The Heading-Error Plant
Compared with the cross-track formulation, the heading-error plant has _one fewer integration_. Starting again from $accent(psi, dot) = v K_"steer" delta_c / L$, only one step is needed to obtain the heading deviation $alpha$ relative to the look-ahead point. The look-ahead point is, by construction, ahead of the vehicle on the path; if the path is locally straight, the line to the look-ahead point is parallel to the path tangent, and the heading error reduces to the angle between the vehicle's forward vector and the path tangent. In the Laplace domain,
$ A(s) / Delta_c(s) = (v K_"steer")/(L) dot 1/s = (v K_"steer") / (L s) $ <eq_heading_plant>
which is a _single integrator_ with a DC gain that scales linearly with $v$, not with $v^2$.

The structural difference between @eqt:eq_xtrack_plant and @eqt:eq_heading_plant is the single most important property of the present chapter, because it has three direct consequences:

#list(
[A PI controller is sufficient for closed-loop stability. The derivative term is no longer necessary—the plant has only one free integrator—and is included only if the error signal is noisy enough to require derivative filtering.],
[The gains scale as $1/v$ instead of $1/v^2$. Gain scheduling across the operating speed range is therefore much gentler.],
[The closed-loop bandwidth that the controller can achieve at fixed gains is higher, because each additional integrator in the plant adds $90 degree$ of phase lag and reduces the available phase margin.]
)

The plant comparison is summarised in @plant_block, which puts the two transfer functions side by side and makes the role of the look-ahead point explicit: by closing the loop on the angle to a point on the path rather than on the perpendicular distance to it, the controller "consumes" one of the two integrators that the cross-track formulation has to handle.

#figure(image("image/plant_comparison.jpeg"), caption: [Block-diagram comparison of the cross-track and heading-error plants. The cross-track formulation contains two integrators—yaw rate to heading, and lateral velocity to cross-track distance—while the heading-error formulation contains only one. The reduction in plant order is the reason why a PI controller is sufficient for the heading-error case, while a full PID is required for the cross-track case.]) <plant_block>

=== Pole Placement
With the plant given by @eqt:eq_heading_plant and a PI controller $C(s) = K_p + K_i / s$, the closed-loop characteristic polynomial reads
$ s^2 + K_"lat" K_p s + K_"lat" K_i, quad K_"lat" = v K_"steer" / L $
Matching with $s^2 + 2 zeta omega_n s + omega_n^2$ and choosing the critical damping $zeta = 1$ yields
$ K_p = (2 omega_n)/K_"lat", quad K_i = (omega_n^2)/K_"lat" $ <eq_heading_gains>

Both gains scale as $1/v$ through $K_"lat"$. The asymptotic comparison with the cross-track formulation is best read graphically: @analytic_cmp shows, in the bottom-right panel, the proportional gain $K_p$ as a function of vehicle speed for the two formulations, normalised so that the value at $30$ km/h is unity. The cross-track curve falls by an order of magnitude when the speed grows from $30$ to $120$ km/h, while the heading-error curve only falls by a factor of four. The practical consequence is that the same heading-error PI controller can be safely operated, with at most a mild gain re-scheduling, across the entire highway-speed range; the cross-track PID, in contrast, is much more sensitive to speed mismatches and would oscillate or diverge if used outside the range it has been tuned for.

=== Look-Ahead Distance Scheduling
The look-ahead point introduces a single design parameter, the look-ahead distance $L_d$. A short $L_d$ produces a controller that reacts strongly to local geometry and that is well-behaved on tight turns but easily destabilised at high speed; a long $L_d$ produces a smooth controller that filters out high-frequency disturbances on the reference path but cuts corners on tight turns. The compromise that is most often adopted in the literature on Pure Pursuit—and that has been retained in the present implementation—is to schedule $L_d$ linearly with the speed of the vehicle:
$ L_d(v) = L_d^"min" + k_L v $
with a minimum $L_d^"min" = 4$ m that protects against pathological behaviour at standstill, and a slope $k_L = 0.6$ s that produces $L_d approx 9$ m at the nominal cruise speed of $30$ km/h. The same kind of linear scheduling is used by the CARLA reference local planner @local_planner for its waypoint-popping criterion, with comparable numerical values.

=== Heading-Error Filtering
A practical consideration that is specific to the heading-error formulation is the noise on the error signal. The look-ahead point is selected from a discrete sampling of the reference path, so the heading error is intrinsically a piecewise-constant signal that exhibits small jumps every time the look-ahead point advances by one waypoint. These jumps are amplified by the derivative term and would produce visible jitter on the steering command. In the implementation, the heading error is therefore low-pass filtered with a first-order infinite impulse response filter of pole $alpha_H$:
$ accent(alpha, tilde)[k] = alpha_H alpha[k] + (1 - alpha_H) accent(alpha, tilde)[k-1] $
with $alpha_H = 0.4$, which corresponds to a cut-off frequency of approximately $2$ Hz at the simulator rate of $20$ Hz. This is well below the Nyquist frequency of the controller and well above the bandwidth of the closed loop, so it removes the per-sample jitter without affecting the dynamic response of the system.

== System Identification and Analytical Tuning <sec_sysid>
The pole-placement formulas @eqt:eq_xtrack_gains and @eqt:eq_heading_gains express the PID gains in terms of two physical parameters: the wheelbase $L$, which is read from the vehicle blueprint through the CARLA Python API, and the steering gain $K_"steer"$, which depends on the specific vehicle model and is not exposed by the API. The latter has to be measured experimentally. In addition, the longitudinal channel of the LKA function—the speed regulator that maintains the cruise speed—has its own parameters that have to be identified.

The identification procedure has been implemented in the standalone script `carla_sysid.py`; it consists of two open-loop step experiments that are recorded with the simulator in synchronous mode at $T_s = 0.05$ s.

=== Longitudinal Step Experiment
The first experiment fits the parameters of a first-order longitudinal model. With the vehicle initially at rest on a long straight road, the throttle is stepped from zero to a fixed value $u_"step" = 0.5$ and held for ten seconds. The resulting speed trajectory $v(t)$ is recorded and fitted, by nonlinear least squares, to the first-order step response
$ v(t) = K u_"step" (1 - e^{-t / tau}) $
where $K$ is the DC gain (in km/h per unit of throttle) and $tau$ is the time constant of the longitudinal dynamics. The model is sufficient because at the moderate accelerations encountered during the experiments, the dominant non-linearity of the powertrain—the throttle-to-torque map—is approximately linear, and the slower aerodynamic drag becomes important only above $80$ km/h.

=== Lateral Step Experiment
The second experiment identifies the steering gain $K_"steer"$. The vehicle is settled at a constant speed $V = 30$ km/h with a simple proportional speed regulator, and a small steering step $delta_c = 0.05$ is applied for $2.5$ s. The yaw rate of the vehicle is recorded directly from the `get_angular_velocity` getter of the CARLA Python API. The steady-state yaw rate $accent(psi, dot)_"ss"$ obtained by averaging the last $25%$ of the trace is then matched against the bicycle-model prediction $accent(psi, dot)_"ss" = (V / L) K_"steer" delta_c$, giving
$ K_"steer" = (accent(psi, dot)_"ss" L) / (V delta_c) $

The duration of the lateral step is kept deliberately short, because once the vehicle starts to drift laterally the cross-track error grows quickly and the small-angle assumptions of the bicycle model are no longer satisfied.

=== Analytical Plot Comparison
With $L$ and $K_"steer"$ identified, the analytical gains of @eqt:eq_xtrack_gains and @eqt:eq_heading_gains can be evaluated and the resulting closed-loop transfer functions can be analysed without running the simulator. @analytic_cmp shows the four canonical control plots that the tuning script `pid_tuning.py` produces from the identified plant parameters: the open-loop magnitude and phase of the loop transfer $L(s) = C(s) G(s)$ for the two formulations (top row), the closed-loop step response of the reference-to-output transfer $T(s)$ (bottom-left), and the speed dependence of the proportional gain $K_p$ (bottom-right).

#figure(image("image/analytical_comparison.png"), caption: [Analytical comparison of the cross-track PID and heading-error PI controllers, computed symbolically from the identified plant parameters. _Top_: open-loop magnitude and phase. _Bottom-left_: closed-loop step response. _Bottom-right_: proportional gain as a function of vehicle speed, normalised at $30$ km/h. The gentler $1/v$ scaling of the heading-error gain, compared with the $1/v^2$ scaling of the cross-track gain, is the main reason why the heading-error formulation is preferred in the operational range of an LKA function.]) <analytic_cmp>

Several observations can be made from these plots. The two open-loop magnitudes coincide above $omega approx 4$ rad/s—at high frequency, both loops are dominated by the fastest pole of the controller—while at low frequency the cross-track loop has a steeper slope that reflects the additional integrator. The phase of the cross-track loop reaches $-180 degree$ around the same frequency at which the heading-error loop is still well above $-90 degree$, which translates into a smaller phase margin and a more oscillatory step response. Both controllers track a unit step, but the cross-track design exhibits a larger overshoot and a longer settling time, even though its bandwidth $omega_n$ has been deliberately set lower than that of the heading-error controller to compensate for the additional plant order.

The bottom-right panel quantifies the gain-scheduling argument that has been made in @sec_heading. At $V = 120$ km/h, the proportional gain of the cross-track controller is more than ten times smaller than its value at $30$ km/h, while the same gain of the heading-error controller is only four times smaller. In a fixed-gain implementation, this means that a cross-track PID tuned at $30$ km/h is unsafe to use even at $50$ km/h, while a heading-error PI tuned at the same speed is acceptable for the entire range $20$–$60$ km/h that covers urban driving and most of the operational design domain of an LKA function.

== Vision-Based Lane Reference <sec_vision>
The third architecture removes the dependence on the pre-recorded `.csv` reference path by reconstructing the centre line of the lane at every tick from the RGB camera feed. The architecture is identical to the heading-error PI controller of @sec_heading from the controller block downward; the only modification is the way in which the look-ahead point is generated. A high-level view of the vision-based pipeline is given on the bottom row of @three_arch.

=== The Lane-Detection Network
Lane detection in road scenes has been a benchmark task in computer vision for over a decade, and the literature offers a variety of architectures with different trade-offs between accuracy, speed, and complexity. The taxonomy adopted in the recent comparative study of Lin et al. @lin2024lane covers semantic-segmentation networks (SCNN @scnn, RESA @resa), row-based classifiers (UFLD @ufld), anchor-based detectors (LaneATT @laneatt, ADNet @adnet), parametric-curve regressors (BezierLaneNet @beziernet) and the recent CLRNet @clrnet family that combines an anchor-based proposal mechanism with row-wise refinement. The implementation supports any model from this list through a pluggable registry stored in the `detection_models` dictionary; for the experiments reported in this thesis, the CLRNet model trained on the TuSimple dataset has been used, because it offers the best trade-off between latency and lane-fitting accuracy in the comparative study cited above.

The detection network operates on a $1280 times 720$ frame extracted from the camera sensor and produces a list of lane lines, each represented as a sequence of pixel coordinates $(u_i, v_i)$. In the present formulation, the reference for the controller is not a single lane line but the _centre line_ of the ego-lane, which has to be reconstructed from the detected boundaries. The reconstruction is performed by the helper function `get_centerline`: only the lane lines that reach the bottom $30%$ of the image are kept—so that adjacent lanes and far-away lines are filtered out—and the closest left and right boundaries to the image centre are paired up. Their interpolated mid-points at a regular sampling along the image $v$-axis form the centre line, which is returned ordered from the closest sample to the furthest.

=== Inverse Perspective Mapping
The centre line returned by the lane-detection network is expressed in pixel coordinates and cannot be used directly by the controller, which works in the body frame of the vehicle. The conversion from pixels to a body-frame position is performed by the standard _inverse perspective mapping_ (IPM) projection, sketched in @ipm_fig.

#figure(image("image/ipm_geometry.jpeg"), caption: [Inverse perspective mapping (side view). A pixel below the horizon back-projects to a unique point on the ground plane, given the camera height $h_"cam"$ and the camera intrinsics $(f_x, f_y, c_u, c_v)$. Pixels above the horizon $v <= c_v$ project to infinity and are discarded.]) <ipm_fig>

Under the assumptions of a pinhole camera with zero pitch, zero roll, zero yaw, and a flat ground plane, every pixel below the horizon corresponds to a unique point on the ground plane. With the camera mounted at height $h_"cam"$ above the road, with focal lengths $f_x = f_y = w / (2 tan("FOV"/2))$ derived from the image width $w$ and the field of view, and with the principal point at $(c_u, c_v) = (w/2, h/2)$, the mapping reads
$ X_"cam" = (h_"cam"  f_y) / (v - c_v), quad Y_"cam" = X_"cam" (u - c_u) / f_x $
where $X_"cam"$ is the longitudinal distance ahead of the camera, in metres, and $Y_"cam"$ is the lateral distance to the right of the camera. The projection is well defined only for pixels below the horizon, that is for $v > c_v$; pixels above the horizon are discarded. A maximum range $X_"cam" <= 40$ m is also enforced, because at larger distances the small angular resolution of the pixel produces unstable lateral estimates. The constant offset of the camera with respect to the rear axle of the vehicle is taken into account by adding $0.8 b_x$ to $X_"cam"$, where $b_x$ is the half-extent of the bounding box of the vehicle.

The output of the IPM block is therefore a sampling of the centre line of the lane in the body frame of the vehicle, in metres, ordered from the closest sample to the furthest. This is exactly the input that the heading-error formulation of @sec_heading expects, with the only difference that the look-ahead point is now selected on a perception-based reference rather than on a pre-recorded one.

=== Polynomial Fitting and Look-Ahead Selection
The samples of the centre line returned by the IPM block are noisy and unevenly spaced. To produce a stable look-ahead point, a low-degree polynomial $y = a_1 x + a_0$ is fitted by least squares to the samples that fall in the longitudinal interval $[0.5, 20]$ m, and the look-ahead lateral coordinate is evaluated as $y_"la" = a_1 L_d + a_0$. A first-degree polynomial—a straight line—has been adopted because the operational scenario consists of mostly straight roads and gentle curves at moderate speed; for higher speeds and tighter curves, a second-degree polynomial would be necessary, with a corresponding increase in sensitivity to outliers. The heading error is then computed as
$ alpha = "atan2"(y_"la", L_d) $
which is the body-frame counterpart of the world-frame definition given in @sec_heading. The same PI controller, with the same low-pass filter on $alpha$, then produces the steering command.

=== Junction Handling
A specific issue that arises with the vision-based formulation, but not with the path-based formulations, is the disappearance of the lane markings inside an intersection. CARLA, like real-world road infrastructure, does not paint lane markings inside junctions, so the lane-detection network either returns nothing or returns lines that belong to the entry and exit lanes of different branches. To prevent the controller from acting on this unreliable input, a junction-detection mechanism has been added on top of the perception pipeline. At every tick, the closest waypoint is queried with `is_junction`; if either this flag is set, or the vehicle is inside one of three pre-flagged buffer regions where the lane markings are known to disappear before `is_junction` flips, the LKA function is temporarily disabled and the control is handed off to the CARLA Traffic Manager autopilot until the vehicle exits the junction. A reset of the integral state of the PI controller and of the look-ahead-distance filter is performed at every re-engagement, so that no transient is propagated from one intersection to the next.

== Method Comparison <sec_comparison>
The three architectures presented in this chapter solve the same lane-keeping problem with progressively richer information and progressively more sophisticated control structure. From a purely control-theoretic standpoint, they can be summarised as in @arch_summary.

#text(size: 9.4558pt, top-edge: "cap-height", bottom-edge: "baseline")[#figure(
  table(
    columns: 4,
    table.header(
      [Property], [Cross-track PID], [Heading-error PI], [Vision-based PI]
    ),
    [Reference signal], [recorded path], [recorded path], [reconstructed centre line],
    [Error signal], [perpendicular distance $e_y$], [look-ahead angle $alpha$], [look-ahead angle $alpha$],
    [Plant order], [2 (double integrator)], [1 (single integrator)], [1 (single integrator)],
    [Required terms], [$P + I + D$], [$P + I$ ($D$ optional)], [$P + I$ ($D$ optional)],
    [Plant gain scaling], [$prop v^2$], [$prop v$], [$prop v$],
    [Gain scheduling], [$prop 1 slash v^2$], [$prop 1 slash v$], [$prop 1 slash v$],
    [Phase margin], [smaller], [larger], [larger],
    [Robustness to noise], [moderate], [good], [depends on detector],
    [Map dependence], [yes (pre-recorded)], [yes (pre-recorded)], [no],
    [Generalisation], [restricted to recorded route], [restricted to recorded route], [unrestricted within ODD],
  ), caption: [Side-by-side comparison of the three lateral-control architectures along the dimensions that are most relevant for an LKA function.]
) <arch_summary>]

The progression from one architecture to the next is informed by a clear control-theoretic rationale rather than by an incremental engineering choice. The move from the cross-track to the heading-error formulation is motivated by the reduction in plant order: by closing the loop on the angle to a look-ahead point rather than on the perpendicular distance to the path, one of the two integrators of the cross-track plant is removed, the derivative term becomes optional, the gain schedule becomes gentler, and the phase margin becomes larger at any fixed bandwidth. The move from the path-based heading-error formulation to the vision-based one is motivated by the removal of the dependence on a pre-recorded reference: the same controller can be used on any road that the lane-detection network has been trained for, at the cost of an additional perception layer that has its own failure modes—most notably inside intersections, which has motivated the introduction of an explicit junction-handling logic.

The numerical evaluation of the three architectures on a common test scenario is the subject of the next chapter, which will quantify the qualitative arguments developed here in terms of cross-track error, lateral RMSE, and steering-command smoothness.
