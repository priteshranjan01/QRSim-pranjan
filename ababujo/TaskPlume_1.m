classdef TaskPlume_1<Task
    % ababujo: Creating a scenario as follows: Three drones moving towards an obstacle(wall)
    % and on the other side of the obstacle, two drones are moving towards each other.
    % One of the 3 drones does not have any detection capability.
    % The second drone can detect anything within a 5 feet distance from it, and when it does it comes to a sudden stop.
    % The third drone can detect anything within 10feet, and when it does- starts moving the other way.
    % The two drones on the other side of the wall should try to avoid the pending collision in someway.
    % in this task all the sensors are noiseless and the wind is
    % turned off.
    
    properties (Constant)
        durationInSteps = 1700;
        N1 = 0;             % drones without any obstacle sensing capability
        N2 = 0;             % drones with the ability to sense anything in the radius of 10f
        N3 = 0;             % drones with the ability to sense anything in the radius of 5f
        N5 = 0;             % drones when sensing another drone tries to fly above it.
        hfix = 15;           % fix flight altitude
        PENALTY = 1000;      % penalty reward in case of collision
    end
    
    properties (Access=public)
        initialX; % initial state of the uavs
        prngId;   % id of the prng stream used to select the initial positions
        PIDs;  % pid used to control the uavs
        f;  % flags to denote sensor picking up some obstacle on its radar
        d;  % flags to denote sensor picking up some other drone on its radar
        p; % flags to denote sensor comes in contact with some contamination
        in;
        C; % completed array
        L;  % Nodes to the left of the centroid
        R;  % nodes to the right of the centroid
        mesh = 0;
        done = 0;
        time =0;
        vt; % to store target velocities
        furthest_pairs;     % pranjan:
        formation_type = "mesh"; 
        number_of_pairs = 1;  
        % pranjan: made N4 a non constant variable to change the number of drones at run time.
        N4 = 36;       % drones when sensing another drone carries straight on assuming the other drones would change its route
                       % pranjan Keep N4 as a square number, this way the initial drones
                       % can be positioned in a nice square grid.
              
    end
    
    methods (Sealed,Access=public)
        
        function obj = TaskPlume_1(state)
            obj = obj@Task(state);
        end
        
        function taskparams=init(obj) %#ok<MANU>
            % loads and returns the parameters for the various simulation objects
            %
            % Example:
            %   params = obj.init();
            %          params - the task parameters
            %
            fprintf("I was called\n");
            if obj.simState.number_of_drones > 0  % Workaround to dynamically change the number of drones at run time. Used to study network density.
                obj.N4 = obj.simState.number_of_drones;
            end
            taskparams.dt = 0.2; % task timestep i.e. rate at which controls
            % are supplied and measurements are received
            
            taskparams.seed = 0; %set to zero to have a seed that depends on the system time
            
            %%%%% visualization %%%%%
            % 3D display parameters
            taskparams.display3d.on = 1;
            taskparams.display3d.width = 1000;
            taskparams.display3d.height = 600;
            
            %%%%% environment %%%%%
            % these need to follow the conventions of axis(), they are in m, Z down
            % note that the lowest Z limit is the refence for the computation of wind shear and turbulence effects
            taskparams.environment.area.limits = [-60 60 -60 60 -90 0];
            taskparams.environment.area.type = 'BoxWithObstaclesArea';
            
            % originutmcoords is the location of the RVC (our usual flying site)
            % generally when this is changed gpsspacesegment.orbitfile and
            % gpsspacesegment.svs need to be changed
            [E N zone h] = llaToUtm([51.71190;-0.21052;0]);
            taskparams.environment.area.originutmcoords.E = E;
            taskparams.environment.area.originutmcoords.N = N;
            taskparams.environment.area.originutmcoords.h = h;
            taskparams.environment.area.originutmcoords.zone = zone;
            taskparams.environment.area.graphics.type = 'AreaWithObstaclesGraphics';
            taskparams.environment.area.graphics.backgroundimage = 'ucl-rvc-zoom.tif';
            %ababujo:obstacles{Column - X Y Z(h) r}
            % taskparams.environment.area.obstacles = taskparams.environment.area.type.obstacles;
            taskparams.environment.area.obstacles = [ ];
            taskparams.environment.area.plume = [10 10 30 25]';  % x,y,z of center and radius.This value shall override the value in BoxWithObstaclesArea file.
            %taskparams.environment.area.plume = [10 40 25 13]';  % x,y,z of center and radius.This value shall override the value in BoxWithObstaclesArea file.            
            
            % GPS
            % The space segment of the gps system
            taskparams.environment.gpsspacesegment.on = 0; %% NO GPS NOISE!!!
            taskparams.environment.gpsspacesegment.dt = 0.2;
            % real satellite orbits from NASA JPL
            taskparams.environment.gpsspacesegment.orbitfile = 'ngs15992_16to17.sp3';
            % simulation start in GPS time, this needs to agree with the sp3 file above,
            % alternatively it can be set to 0 to have a random initialization
            %taskparams.environment.gpsspacesegment.tStart = Orbits.parseTime(2010,8,31,16,0,0);
            taskparams.environment.gpsspacesegment.tStart = 0;
            % id number of visible satellites, the one below are from a typical flight day at RVC
            % these need to match the contents of gpsspacesegment.orbitfile
            taskparams.environment.gpsspacesegment.svs = [3,5,6,7,13,16,18,19,20,22,24,29,31];
            % the following model is from [2]
            %taskparams.environment.gpsspacesegment.type = 'GPSSpaceSegmentGM';
            %taskparams.environment.gpsspacesegment.PR_BETA = 2000;     % process time constant
            %taskparams.environment.gpsspacesegment.PR_SIGMA = 0.1746;  % process standard deviation
            % the following model was instead designed to match measurements of real
            % data, it appears more relistic than the above
            taskparams.environment.gpsspacesegment.type = 'GPSSpaceSegmentGM2';
            taskparams.environment.gpsspacesegment.PR_BETA2 = 4;       % process time constant
            taskparams.environment.gpsspacesegment.PR_BETA1 =  1.005;  % process time constant
            taskparams.environment.gpsspacesegment.PR_SIGMA = 0.003;   % process standard deviation
            
            % Wind
            % i.e. a steady omogeneous wind with a direction and magnitude
            % this is common to all helicopters
            taskparams.environment.wind.on = 0;  %% NO WIND!!!
            taskparams.environment.wind.type = 'WindConstMean';
            taskparams.environment.wind.direction = degsToRads(45); %mean wind direction, rad clockwise from north set to [] to initialise it randomly
            taskparams.environment.wind.W6 = 0.5;  % velocity at 6m from ground in m/s
            
            %%%%% platforms %%%%%
            % Configuration and initial state for each of the platforms
            
            for i=1:obj.N4
                taskparams.platforms(i).configfile = 'Detect10_config';
            end
            
            % get hold of a prng stream
            obj.prngId = obj.simState.numRStreams+1;
            obj.simState.numRStreams = obj.simState.numRStreams + 1;
        end
        
        %ababujo: reset() is called initially to iniitialize the positions
        % and in this case the PIDs
        function random_formation(obj)
            % This is an equivalent function as to
            % uniform_random_formation. 
            warning("DEPRECATED. Use uniform_random_formation instead");
            N = obj.N4;
            x_min = -20;
            x_max = 20;
            y_min = -20;
            y_max = 20;
            z_min = 30;
            z_max = 50;
            for drone=1:N
                x = x_min + rand() * (x_max - x_min);
                y = y_min + rand() * (y_max - y_min);
                z = z_min + rand() * (z_max - z_min);
                %fprintf("\n%f %f %f\n", x, y, -z);               
                obj.simState.platforms{drone}.setX([x; y; -z; 0;0;0;]);
                obj.PIDs{drone} = VelocityPID(obj.simState.DT);
            end
        end
        
        function uniform_random_formation(obj)
            % Use this to generate random drones in a 3D Volume specified
            % by the below coordinates.   
          
            N = obj.N4;
            x_min = -30;
            x_max = 30;
            y_min = -30;
            y_max = 30;
            z_min = 20;
            z_max = 50;
            seed = int32(rand() * 10000);
            P = gallery('uniformdata', N, 3, seed);
            for drone=1:N
                x = x_min + P(drone, 1) * (x_max - x_min);
                y = y_min + P(drone, 2) * (y_max - y_min);
                z = z_min + P(drone, 3) * (z_max - z_min);
                obj.simState.platforms{drone}.setX([x; y; -z; 0;0;0;]);
                obj.PIDs{drone} = VelocityPID(obj.simState.DT);
                set_targetX = abs(obj.simState.platforms{drone}.target_velocity(1));
                rand_target = -set_targetX + 2*set_targetX * rand(3,1);
                obj.simState.platforms{drone}.target_velocity = rand_target;
            end
        end

        
        function random_speherical(obj)
            % In spehrical formation type the nodes shall be positioned on the surface of the plume in a random distribution. 
            N = obj.N4;
            theta = 2 * pi * rand(1,N);  % Generate 36 values between 0 to 360 degrees.
            phi = asin(-1+2*rand(1,N));
            center = obj.simState.environment.area.plume(1:3);
            radius = obj.simState.environment.area.plume(4);
            [X,Y,Z] = sph2cart(theta,phi,radius);
            X = X + center(1);
            Y = Y + center(2);
            Z = Z + center(3);
            for idx = 1:N
                obj.simState.platforms{idx}.setX([X(idx); Y(idx); -Z(idx); 0; 0; 0]);
                obj.PIDs{idx} = VelocityPID(obj.simState.DT);
            end
        end
     
       function mesh_formation(obj)
            N = obj.N4;
            X = floor(sqrt(N));  % N BETTER BE A PERFECT SQUARE.
            
%             % For 9 drones, the below will be reasonable
%             Y_seperation = 15;  Z_seperation = 15; Z_base = 0; 
%             Y_base = 50;    % Y coordinate of Drone #1 X_base = -10;   
            % For 36 drones, the below will be reasonable
            Y_seperation = 10;  Z_seperation = 10; Z_base = -5; 
            Y_base = 44;    % Y coordinate of Drone #1 
            X_base = -55;   

            for hor_row = 1:X
                for ver_col = 1:X
                    idx = ((hor_row-1) * X + (ver_col-1));
                    val = [X_base; Y_base - (hor_row -1) * Y_seperation; Z_base - (ver_col-1) * Z_seperation; 0; 0; 0];
                    obj.simState.platforms{idx+1}.setX(val);
                    obj.PIDs{idx+1} = VelocityPID(obj.simState.DT);
                end
            end
        end
 
        
        function mesh_formation1(obj)
            N = obj.N4;
            X = floor(sqrt(N));  % N BETTER BE A PERFECT SQUARE.
            
            % For 9 drones, the below will be reasonable
            Y_seperation = 15;  Z_seperation = 15; Z_base = 0; 
            Y_base = 50;    % Y coordinate of Drone #1 X_base = -10;   
            % For 36 drones, the below will be reasonable
%             Y_seperation = 10;  Z_seperation = 10; Z_base = 5; 
%             Y_base = 44;    % Y coordinate of Drone #1 
            X_base = -10;   

            for i = 1:X
                for j = 1:X
                    idx = ((i-1) * X + (j-1)) + 1;
                    obj.simState.platforms{idx}.setX([X_base; Y_base - i * Y_seperation; Z_base - j * Z_seperation; 0; 0; 0]);
                    obj.PIDs{idx} = VelocityPID(obj.simState.DT);
%                     obj.f{idx} = 0;
%                     obj.d{idx} = 0;
%                     obj.p{idx} = 0;
%                     obj.in{idx} = 0;
                end
            end
        end
        
        
        function reset(obj)
            switch obj.formation_type
                case "random"
                    obj.uniform_random_formation();
                case "spherical"
                    obj.random_speherical();
                otherwise
                    obj.number_of_pairs = min(20, obj.number_of_pairs);  
                    obj.mesh_formation();
            end
            N = obj.N4;
            src_dst_pairs = zeros(N * N, 3);
            for i=1:N
                my_coord = obj.simState.platforms{i}.getX(1:3);
                for j=1:N
                    peer_coord = obj.simState.platforms{j}.getX(1:3);   
                    m_dst = pdist([my_coord';peer_coord'], 'euclidean');  % Should be 0 when i==j
                    obj.simState.platforms{i}.distances = [obj.simState.platforms{i}.distances, m_dst];
                    %fprintf("Me = %d peer = %d, ideal dist = %f\n", i, j, m_dst);
                    idx = (i-1) * N + j;
                    src_dst_pairs(idx, :) = [i, j, m_dst];
                end
            end
%             [~, idx] = unique(src_dst_pairs(:, 3));
%             src_dst_pairs = src_dst_pairs(idx, :);
            src_dst_pairs = sortrows(src_dst_pairs, 3, 'descend');  
            mmd = floor(size(src_dst_pairs, 1)/2);
            obj.furthest_pairs = src_dst_pairs(mmd, :);

%            obj.furthest_pairs = src_dst_pairs(1:obj.number_of_pairs, :);
        end
  

        function acc_mag = get_acceleration_mag(obj, m_dst, me, peer)
            mass = obj.simState.platforms{me}.MASS;
            f_max = obj.simState.platforms{me}.F_MAX;
            d_ideal = obj.simState.platforms{me}.distances(:,peer);  
            elastic = obj.simState.platforms{me}.elasticity;
            buff = d_ideal * elastic;
            d_max = d_ideal + buff;
            d_min = buff;
            d_max_ex = d_max + buff;
            force = force_fields("sigmoid_field", f_max, m_dst, d_min, d_max, d_max_ex);
            acc_mag = force / mass;
        end
        
        function UU = step1(obj, U)
            % Used only in performance evaluation. Doesn't do any force
            % calculation. The drones keep on moving with their initial
            % velocity.
            obj.time = obj.time +1;
            N = obj.N4;
            UU = zeros(5, N);
            for me= 1:N
                target_vel = obj.simState.platforms{me}.target_velocity;
                %target_vel = target_vel + [2; 0;0];
                UU(:,me) = obj.PIDs{me}.computeU(obj.simState.platforms{me}.getX(), target_vel ,0);
            end
        end
        
        % in step(), the drone takes a step based on its relative position
        % with each other and also to other dronee, obstacles, etc..
        function UU = step(obj,U)
            obj.time = obj.time +1;
            
            N = obj.N4;
            UU = zeros(5,N);
            % ob = obj.simState.platforms{i}.ObDetect();
            for me = 1: N
                ob = obj.simState.platforms{me}.PlumeDetect(me);
                if(ob ==1 || obj.simState.platforms{me}.isValid() == 0) % If a UAV detects a plume, or it collided with another drone, it stops
                    UU(:,me) = obj.PIDs{me}.computeU(obj.simState.platforms{me}.getX(),[0;0;0],0);
                else
                    c_acc_vec = [0;0;0];
                    if obj.simState.send_coordinates == 1  % If drones transmit their coordinates
                        % Check if the current drone is outside of d_min and
                        % d_max range.
                        my_coord = obj.simState.platforms{me}.getX(1:3);
                        c_ct = 0;
                        for peer=1:N
                            if me ~= peer && obj.simState.platforms{peer}.isValid() == 1
                                peer_data = obj.simState.platforms{me}.location_table(peer);
                                peer_coord = peer_data{1};
                                if norm(peer_coord) ~= 0
                                    m_dst = norm(my_coord - peer_coord); % 'euclidean' dist
                                    c_acc_mag = obj.get_acceleration_mag(m_dst, me, peer);
                                    if c_acc_mag ~= 0
                                        dir_vec = (peer_coord - my_coord);
                                        dir_vec = dir_vec / norm(dir_vec);
                                        c_acc_vec = c_acc_vec + dir_vec * c_acc_mag;
                                        c_ct = c_ct + 1;
                                    end
                                end
                            end
                        end
                        if c_ct > 1
                            c_acc_vec = c_acc_vec / c_ct;
                        end
                    end
                    res_acc_vec = c_acc_vec;
                    if norm(res_acc_vec) ~= 0
                        draw_force_vector = 0;
                        if draw_force_vector == 1
                        % the below line shall draw force vectors on
                        % the UI.
                            quiver3(my_coord(1),my_coord(2),my_coord(3), res_acc_vec(1), res_acc_vec(2), res_acc_vec(3));
                        end
                        vel_vec_initial = obj.simState.platforms{me}.getX(7:9);
                        vel_vec_target = vel_vec_initial + res_acc_vec * obj.simState.task.dt;
                        obj.simState.platforms{me}.target_velocity = vel_vec_target;
                        UU(:,me) = obj.PIDs{me}.computeU(obj.simState.platforms{me}.getX(), vel_vec_target, 0);
                    else
                        % If UAV_i detected a plume then move towards UAV_i
                        % Else keep moving in the original direction.
                        % UU(:,me) = obj.PIDs{me}.computeU(obj.simState.platforms{me}.getX(),U(:,me),0);
                        % The previous logic was that if there is no
                        % resultant force then move along the X axis. This
                        % lead to jerks in the drone's motion. Uncomment
                        % the above line and comment out the next two line 
                        % to get that behaviour. 
                        target_vel = obj.simState.platforms{me}.target_velocity;
                        UU(:,me) = obj.PIDs{me}.computeU(obj.simState.platforms{me}.getX(), target_vel ,0);
                    end
                end
            end
        end
        
        
        function updateReward(~,~)
            % updates reward
            % in this task we only have a final cost
        end
        
        function r=reward(obj)
            % returns the total reward for this task
            
            valid = 1;
            for i=1:length(obj.simState.platforms)
                valid = valid &&  obj.simState.platforms{i}.isValid();
            end
            
            if(valid)
                r = obj.currentReward ;
            else
                % returning a large penalty in case the state is not valid
                % i.e. one the drones is out of the area, there was a
                % collision or one of the drones has crashed
                r = - obj.PENALTY;
            end
        end
    end
end
