= Interface Co-Simulation Design
== Selecting the Suitable Simulator
 The development and testing of autonomous driving technologies require a robust simulation environment. This environment must accurately model the real world, including vehicles, pedestrians, and various environmental conditions, while also providing comprehensive support for sensor simulation and enabling integration with analytical tools. After a detailed evaluation of existing simulators, including the Waymo Simulator, LGSVL Simulator, Sim4CV, and CARLA Simulator, based on critical features such as graphic quality, the accuracy of the physics engine, sensor simulation capabilities, the simulation of traffic and pedestrians, weather conditions, the ability to simulate different times of day, CARLA Simulator has been identified as the most suitable choice for my research objectives. CARLA provides high-quality graphics with Unreal Engine 4 @unreal_engine_4 and its physics engine accurately models vehicle dynamics and environmental interactions, offering a solid foundation for testing autonomous driving algorithms under various conditions. Moreover, its ability to simulate a wide range of sensors used in autonomous vehicles, such as cameras, LIDAR, radar, and GNSS, with high fidelity is crucial for the development and testing of perception algorithms. CARLA also excels in simulating dynamic traffic scenarios and pedestrian behaviors, facilitating comprehensive testing of autonomous driving systems in complex urban environments. The capability to simulate different weather conditions and times of day is important for assessing the performance of autonomous vehicle systems under various environmental conditions. For my research, CARLA’s Python API facilitates easy integration with an external controller, providing a seamless workflow for data analysis and algorithm testing. Consequently, CARLA Simulator’s advanced graphics, accurate physics engine, extensive sensor simulation capabilities, and effective traffic and pedestrian simulation set it as the ideal choice for my autonomous driving research. Its compatibility with Python API further supports my analytical and development needs, making it the most suitable simulator for my project.
 == Modeling the Car in the Environment
In order to control a vehicle in the simulation, the controller must recognize the vehicle model. For this, a model of the vehicle is needed. Various models can be used when modeling the vehicle. Among these, the most commonly used ones usually offer a good balance between simplicity and accuracy, capable of representing the vehicle’s motion dynamics and control systems. In line with the needs of this project, the Dynamic Single-Track (DST) model has been chosen (shown in @single_track). The DST model (bicycle model) can be modeled with single-track wheels (one front and one rear wheel). This is equivalent to a model where the right and left sides of a four-wheeled vehicle are considered equal.
#figure(image("image/single track model.jpeg"), caption: [Single Track Model]) <single_track>
*Vehicle variables:* \
- $δ_f$: steering angle.\
- $β$: vehicle sleep angle = angle between the vehicle longitudinal axis and velocity\
- $ β_f, β_r$: tire slip angles = angles between the tire longitudinal axis and velocity.
*Vehicle parameters:*\
- CoG: center of gravity
- $m,J$: mass and moment of inertia
- $l_f$: distance CoG - front wheel center
- $l_r$: distance CoG - rear wheel center
- $c_f,c_r$: front/rear cornering stiffnesses.
#figure(image("image/vehicle reference system.jpeg"), caption: [Vehicle Reference System]) <Vehicle_reference>
*Vehicle Dynamic parameters:*
- $X,Y$: coordinates of the vehicle CoG in an inertial reference frame (shown in @Vehicle_reference)
- $ψ$: yaw angle
- $ω_ψ = accent(ψ,.) $: yaw rate
- $arrow(v) ≡ V$: velocity vector in the inertial frame
- $v_x$: longitudinal speed $=arrow(v)$ component along the longitudinal axis
- $v_y$: lateral speed $=arrow(v)$ component along the lateral (transverse) axis
- $a_x$: longitudinal acceleration in the inertial frame.
The state equations of the DST model are:
$ accent(X,.) = V_x cos ψ−V_y sin ψ $
$ accent(Y,.) = V_x sin ψ + V_y cos ψ $
$ accent(ψ,.) =ω_ψ $
$ accent(V,.)_x = V_y ω_ψ +a_x $
$ accent(V,.)_y = −V_x ω_ψ + 2/m (F_(y f) + F_(y r)) $
$ accent(ω,.)_ψ = 2/J (l_f F_(y f) −l_r F_(y r)) $

where $F_(y f)$ and $F_(y r)$ are the lateral forces exchanged between tire and road.

For the tire model, there are several tire model options:
#block(above: 10.12mm)[
*Linear (for *$V_x = c o n s t$*) tire model:*
$  F_(y f) = −C_f β_f, #h(1.5em)F_(y r) = −C_r β_r $
$ β_f = (V_y +l_f ω_ψ)/V_x − δ_f,#h(1.5em) β_r = (V_y −l_r ω_ψ)/V_x $]
*Nonlinear simplified tire model:*
$ F_(y f) = −C_f β_f cos δ_f, #h(1.5em) F_(y r) = −C_r β_r $
$  β_f = arctan((V_y +l_f ω_ψ)/V_x) −δ_f, #h(1.5em) β_r = arctan((V_y −l_r ω_ψ)/V_x) $
*Nonlinear Pacejka’s tire model:*
$ F_(y f) = −f_p(β_f)cos δ_f,#h(1.5em) F_(y r) = −f_p(β_r) $
where $β_f$ and $β_r$ and $f_p (β)$ is given by the Pacejka’s magic formula.
*Pacejka’s magic formula:*
$  f_p (β) = p_1 sin(p_2 arctan(p_3 β − p_4(p_3 β − arctan(p_3 β)))) $
$p_1$: peak value, $p_2$: shape factor, $p_3$: stiffness factor, $p_4$: curvature factor. Linearizing this formula, we find $p_1 p_2 p_3 = C_f$ (or $C_r$).
#figure(image("image/friction coef.jpeg"), caption: [Friction Coefficents in different conditions]) <friction_coef>
In the real world conditions, these parameters are really hard to measure or estimate because they change based on the road conditions (see @friction_coef).

The real parameters of the vehicle in the simulation environment have been found with the help of Carla’s `Vehicle.physics` command.
#block(above: 10.12mm)[*Vehicle Parameters Values*]
- $m$: 1318kg
- $J$: 2500kg/m#super[2]
- $l_f$: 1.54m
- $l_r$: 1.51m
- $c_f$: 15000N/rad
- $c_r$: 15000N/rad

=== Dispatching To Obtain Throttle-Brake Value From Acceleration Value
To control a vehicle in the Carla simulator, we need three pieces of information: steering angle, throttle, and brake commands. However, our model generates $a x$ data. It is not possible to directly provide this data to Carla because this information only tells us about the acceleration or deceleration of the vehicle and the magnitude of these changes. Therefore, we need to scale this data to use it for throttle-brake information. To do this, we perform dispatching. In the context of control, “dispatching” usually refers to the process of distributing tasks or resources according to certain criteria or algorithms.

To accomplish this, we first need specific reference values. These reference values should be collected according to many different scenarios to ensure they are suitable for every scenario, not just one. In our case, data were collected for three different scenarios: when the vehicle completes a straight path in a sine wave pattern, when continuous braking and accelerating are performed on a straight road, and finally, when only accelerating is done and the vehicle slows down without braking due to its own weight. The data include the vehicle’s $a x$ acceleration value, and throttle and brake values. By examining these accelerations, the priorities of throttle and brake values are determined for acceleration and deceleration situations. For instance, it is not always necessary to brake for negative acceleration values; reducing the throttle can also achieve the necessary speed reduction. Therefore, each value has its weight. Also, there is a range within which each command should be applied. These ranges can be determined using an if/else structure based on the acceleration value. The commands to be applied within these ranges are found by dividing the $a x$ value by certain weight values. Consequently, the throttle and brake values are instantaneously derived from the $a x$ value and provided to the vehicle in the Carla environment for application. As explained above, these values were found by analyzing reference data and through trial and error. The code for the if/else structure that creates the intervals for applying these values and commands is provided below.

== Data Gathering with Autonomous Driving Mode
A reference point was selected from the Carla Map to collect reference data. The vehicle was spawned at this reference point. A simulation duration was determined based on a finish point we had predetermined. The vehicle was moved using Carla’s autonomous driving mode. During this time, the necessary reference position, waypoint data, yaw angle, and speed data were recorded into a ```.csv``` file at intervals of $T_s = 0.05$ seconds. Once the required simulation duration was completed, the vehicle was removed from the map.
#raw("
...

def carla_data_collector(vehicle: carla.Vehicle):
    time = carla.Timestamp.frame
    transform = vehicle.get_transform()
    location = transform.location
    location_dictionary = {\"x\": location.x, \"y\": location.y, \"z\": location.z}
    rotation = transform.rotation
    rotation_dictionary = {\"pitch\": rotation.pitch, \"yaw\": rotation.yaw, \"roll\": rotation.roll}
    velocity = vehicle.get_velocity()
    velocity_dictionary = {\"x\": velocity.x, \"y\": velocity.y, \"z\": velocity.z}
    acceleration = vehicle.get_acceleration()
    acceleration_dictionary = {\"x\": acceleration.x, \"y\": acceleration.y, \"z\": acceleration.z}
    angular_velocity = vehicle.get_angular_velocity()
    angular_velocity_dictionary = {\"x\": angular_velocity.x, \"y\": angular_velocity.y, \"z\": angular_velocity.z}
    vehicle_world = vehicle.get_world()
    waypoint = vehicle_world.get_map().get_waypoint(location)
    waypoint_dictionary = {\"x\": waypoint.transform.location.x, \"y\": waypoint.transform.location.y, \"z\": waypoint.transform.location.z}
    all_data = {\"time\": time, \"location\": location_dictionary, \"rotation\": rotation_dictionary, \"velocity\": velocity_dictionary, \"acceleration\": acceleration_dictionary, \"angular_velocity\": angular_velocity_dictionary, \"waypoint\": waypoint_dictionary}
    return all_data

def carla_data_collector_2(vehicle: carla.Vehicle):
    world = vehicle.get_world()
    frame = world.get_snapshot().frame
    waypoint = vehicle.get_world().get_map().get_waypoint(vehicle.get_transform().location)

    waypoint_location = waypoint.transform.location
    waypoint_forward_vector = waypoint.transform.get_forward_vector()
    vector_x = waypoint_forward_vector.x
    vector_y = waypoint_forward_vector.y
    waypoint_dictionary = {\"x\": waypoint_location.x, \"y\": waypoint_location.y, \"vector_x\": vector_x, \"vector_y\": vector_y}
    return waypoint_dictionary
    
    ...
    
data = {
    \"waypoint_x\": [],
    \"waypoint_y\": [],
    \"vector_x\": [],
    \"vector_y\": []
}

...

all_data = carla_data_collector_2(ego_vehicle)
    if not data[\"waypoint_x\"] and not data[\"waypoint_y\"]:
        data[\"waypoint_x\"].append(all_data[\"x\"])
        data[\"waypoint_y\"].append(all_data[\"y\"])
        data[\"vector_x\"].append(all_data[\"vector_x\"])
        data[\"vector_y\"].append(all_data[\"vector_y\"])
    else:
        if all_data[\"x\"] != data[\"waypoint_x\"][-1] and all_data[\"y\"] != data[\"waypoint_y\"][-1]:
            data[\"waypoint_x\"].append(all_data[\"x\"])
            data[\"waypoint_y\"].append(all_data[\"y\"])
            data[\"vector_x\"].append(all_data[\"vector_x\"])
            data[\"vector_y\"].append(all_data[\"vector_y\"])", lang: "python", block: true)
== Data Gathering with Manual Driving Mode
The first capability that we demonstrate with CARLA is localization, which allows our ego-vehicle to determine its pose in the world. Two coordinate frames: the map frame, which is a coordinate frame that is fixed at the initial position of the map, and the vehicle frame, which is a coordinate frame attached to the middle of the rear axle of the vehicle. For our particular experiment, we record the vehicle’s accurate pose while traversing a curved-straight route in the Town10. In the Python API, there is a class that comprises all the localization information for an actor at a certain moment in time; its methods comprise Getters such as ``` get_acceleration```, ``` get_velocity```, ``` get_transform```, and ``` get_angular_velocity```- which in our case we utilize the ``` get_transform``` method which includes both location of the object ($X$, $Y$, $Z$ from the origin of the map) in meters, and its rotation characteristics from which we utilize the yaw values. More concisely, $X$ and $Y$ coordinates were our focus, as in the map chosen, the road is entirely flat. Hence only these two coordinates remain crucial for tracking the vehicle’s trajectory. Also, the Yaw angle, describing the orientation of the map’s coordinate system, is essential for indication of the direction the vehicle is facing. Therefore for curved paths, which our scenarios contain, it is important.

Some additional considerations also are to be noted, such as the sampling rate, which determines the time step of the data collection. We have chosen $0.1$, indicating not too sparse to miss some critical dynamics, especially for sharp turns, and also not too frequent leading to redundant information.

After initializing the scenario and ego vehicle (based on the preferences), based on the duration of the scenario depending on the controls of the car (throttle, brake, and steering commands), we record the data of the vehicle at each time step; for better understanding the following Script used in the development is provided;

#raw("
import carla
import pandas as pd

# A dictionary that accumulates one row of data per simulation step
data = {
    \"frame\": [], \"x\": [], \"y\": [], \"yaw\": [],
    \"v_x\": [], \"v_y\": [], \"a_x\": [],
    \"throttle\": [], \"brake\": [], \"steer\": []
}

while not crashed:
    world.tick()                       # Advance the synchronous simulation
    snapshot = world.get_snapshot()
    transform = ego_vehicle.get_transform()
    velocity = ego_vehicle.get_velocity()
    acceleration = ego_vehicle.get_acceleration()
    control = ego_vehicle.get_control()

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

    # ... PyGame rendering and event handling ...

pd.DataFrame(data).to_csv(\"manual_drive_log.csv\", index=False)", lang: "python", block: true)

In manual driving mode, the autopilot is disengaged with `vehicle.set_autopilot(False)` and the user is given full control of throttle, brake, and steering through the keyboard. Each pressed key is captured as a PyGame event and is translated into a `carla.VehicleControl` object that is then applied to the ego vehicle in the simulator. While the user drives, the same getters introduced for the autonomous mode are queried at every simulation tick, so that the resulting `.csv` file shares the same structure for both modes and can be loaded by the controller without any additional preprocessing.

This dual-mode acquisition serves two purposes. First, it provides reference trajectories for the dispatcher tuning and for the controller design, since the autonomous mode of CARLA produces well-formed paths along the center of the lane. Second, it allows the recording of edge cases that are hard to reproduce automatically—for example aggressive lane changes, harsh braking, or following curves at the limit of stability—because they can be performed deliberately by a human driver. The two `.csv` files are then used as the input data set for the lane keeping assist controller described in @ch3[Chapter].