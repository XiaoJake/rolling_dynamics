function param = derive_rolling_dynamics(param)
disp('Calculating Rolling Dynamics...')

%% Initialize Hand Variables
% Positions
syms theta_h_ beta_h_ gamma_h_ real
Phi_h_ = [theta_h_; beta_h_; gamma_h_]; % Euler angles for {h} frame in {s} frame

syms x_h_ y_h_ z_h_ real;
r_h_ = [x_h_; y_h_; z_h_]; % position of {h} frame in {s} frame


% Body Velocities of Hand
syms omegax_h_ omegay_h_ omegaz_h_ real 
omega_h_ = [omegax_h_; omegay_h_; omegaz_h_]; % rotational body velocity  in {h} frame

syms vx_h_ vy_h_ vz_h_ real 
v_h_  = [vx_h_; vy_h_; vz_h_]; % linear body frame in {h} frame

Vh_ = [omega_h_;v_h_]; % Body twist of the hand 
states_hand_ = [Phi_h_; r_h_; omega_h_; v_h_]; % full hand state 


% Hand Controls:
% We assume the hand accelerations are directly controlled 
% (\theta, \beta, \gamma, x, y, z)
syms alphax_h_ alphay_h_ alphaz_h_ ax_h_ ay_h_ az_h_ real; 
dVh_ = [alphax_h_; alphay_h_; alphaz_h_; ax_h_; ay_h_; az_h_];


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Derive Hand Dynamics Equation 
% Hand is directly acceleration controlled 
% States: 
% [theta, beta, gamma, rhx, rhy, rhz, ...
%   omega_x, omega_y, omega_z, v_x, v_y, v_z, ... 

% Hand dynamics equation
%***** return hand dynamics export hand dynamics
% Dynamics Equations 
Rsh_euler_ = fEulerToR(Phi_h_,'XYZ'); % Rotation matrix from xyz euler angles 
%omega_h_ = Kh_*dPhi_h_
Kh_ = KfromR(Rsh_euler_,Phi_h_);

dxddx_hand=simplify([inv(Kh_)*omega_h_;...    % Rotational velocities  inv(Kh_) * omega_h_ = dPhi_h_
                    Rsh_euler_ * v_h_;... % Linear velocities in space frame 
                    dVh_]);                  % Accelerations
param.dynamics.dxddx_hand = dxddx_hand; 
%matlabFunction(dxddx_hand,'file',[dir, 'autoGen_f_handDynamics_fast'],'Vars',{t_, states_hand_, dV_h_});




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Derive Object Dynamics Equation 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% T matrices
    % **** put into functions.symbolic.T R r
    % Between frames c_o and c_h 
    Rpsi_ = param.kinematics.local_geometry.Rpsi_; 
    Rchco_ = [Rpsi_, zeros(2,1);...
              0, 0, -1];
    Rchco_ = Rchco_;
    Tchco_= RpToTrans(Rchco_,[0;0;0]);

    % Object
    Toco_ = simplify(param.kinematics.local_geometry.object.Tici_);
    [Roco_, r_oco_] = TransToRp(Toco_);

    %  Hand
    Thch_ = simplify(param.kinematics.local_geometry.hand.Tici_);
    [Rhch_, r_hch_] = TransToRp(Thch_);

    Toch_ = simplify(Toco_*TransInv(Tchco_)); 
    
    Tcho_ = TransInv(Toch_);
    Toh_ = simplify(Toco_ * TransInv(Tchco_) * TransInv(Thch_)); 
       
    % Make functions here? 
  
%% Calculating Equation 7 from paper

% Include rolling/pure rolling acceleration constraints 
friction_model = param.options.friction_model;
Alpha_ = param.variables.Alpha_; 
if strcmp(friction_model,'rolling') % Rolling
    %***** add to param.variables
    syms fx_ fy_ fz_ real
    ch_F_contact = [zeros(3,1); fx_; fy_; fz_];
    dVrel = [Alpha_; param.kinematics.axyz_]; % relative accelerations at the contact
    %Vrel = [Omega_;0;0;0];  % relative twist at the contact
    %nFree = 3; 
elseif strcmp(friction_model,'pure-rolling') % Pure Rolling
    %***** add to param.variables
    syms tau_z_ fx_ fy_ fz_ real
    ch_F_contact = [zeros(2,1); tau_z_; fx_; fy_; fz_];
    dVrel = [Alpha_(1:2); param.kinematics.alpha_z_; param.kinematics.axyz_]; % relative accelerations at the contact
    %Vrel = [Omega_(1:2);0;0;0;0]; % relative twist at the contact
    %nFree = 2; 
end

    % Adjoint expressions
    Ad_Toch_ = Adjoint(Toch_); 
    Ad_Tcho_ = Adjoint(Tcho_);
    Ad_Toch_ = Adjoint(TransInv(Tcho_));
    Ad_Toh_ = Adjoint(Toh_); 
    
    Go = param.bodies.object.Go; % Object Spatial Inertia Matrix
    omega_rel_ = param.kinematics.omega_rel_fdqo_; 
    Vrel_ = [omega_rel_;0;0;0];  % relative twist at the contact
    Vo_ = Ad_Toh_*Vh_ + Ad_Toch_ * Vrel_; % From Eq 2
    ad_Vo = ad(Vo_);

    % Wrench Expressions
    gravity = param.dynamics.gravity;
    mass_o = param.bodies.object.mass_o;
    s_wrench_g_ = [0;0;0;0;0;-gravity*mass_o];
    Tho_ = TransInv(Toh_); 
    Rho_ = Tho_(1:3,1:3); 
    Ros_ = RotInv(Rsh_euler_ * Rho_ );
    o_wrench_g_ = simplify(blkdiag(Ros_,Ros_)*s_wrench_g_);

    % Solve for K4
    Rcho_ = Tcho_(1:3,1:3); 
    omega_o_ = Vo_(1:3); 
    o_r_opo_ = param.bodies.object.fo_; 
    h_r_hph_ = param.bodies.hand.fh_; 
 % ****** Return K4
    K4_ = ...
    Ad_Toh_ * [zeros(3,1); VecToso3(omega_h_) * (VecToso3(omega_h_) * h_r_hph_)]...
    -Ad_Toch_* [VecToso3(omega_rel_)*(Rcho_*omega_o_) ;zeros(3,1)] ...
    -[zeros(3,1); VecToso3(omega_o_) * (VecToso3(omega_o_)*o_r_opo_)]; 

    dVh_; % Hand accelerations 

    % Equation 7: LHS = RHS + RHS2 * dVh_
    %LHS_ = Ad_Toch_*dVrel - inv(Go)*Ad_Tcho_'*ch_F_contact;
    RHS1_ = inv(Go)*(ad_Vo'*Go*Vo_ + o_wrench_g_) - K4_;
    %RHS2_ = - Ad_Toh_;


%% Deriving rolling dynamics from Eq (8) and (9)
P = param.bodies.P;
P_ = param.bodies.P_;
a_ = - inv(Go)*Ad_Tcho_'; 
if strcmp(friction_model,'rolling') % Rolling (Eq 8)
    K5_ =  subs([Ad_Toch_(:,1:3), a_(:,4:6)], P_,P); % from LHS_ of Eq (7)
    K6_ = subs(RHS1_ - Ad_Toch_(:,4:6)*dVrel(4:6) + a_(:,1:3) * ch_F_contact(1:3), P_,P);
elseif strcmp(friction_model,'pure-rolling') % Pure Rolling (Eq 9)
    K5_ = subs([Ad_Toch_(:,1:2), a_(:,3:6)], P_,P); % from LHS_ of Eq (7)
    K6_ = subs(RHS1_ - Ad_Toch_(:,3:6)*dVrel(3:6) + a_(:,1:2) * ch_F_contact(1:2), P_,P); 
end

if param.options.is_simplify
    K5_ = simplify(K5_);
    K6_ = simplify(K6_);
    Ad_Toh_ = simplify(Ad_Toh_);
end

param.dynamics.K5_ = K5_;
param.dynamics.K6_ = K6_;
param.dynamics.Ad_Toh_ = Ad_Toh_;


%% Return
disp('    DONE: Calculating Rolling Dynamics.')
end