
if exist('buck_params.m','file') == 2
    buck_params;   
else
    error('build_mpc:MissingFile', 'Required file "buck_params.m" not found on path.');
end

required = {'Vin','Vout','Rload','L1','C1','Ts'};
for k = 1:numel(required)
    if ~exist(required{k}, 'var')
        error('build_mpc:MissingVar', 'Required variable "%s" not found in buck_params.m', required{k});
    end
end

if ~exist('Vd','var'), Vd = 0; end
if ~exist('Ron','var'), Ron = 0; end
if ~exist('Vref','var'), Vref = Vout; end

fprintf('Loaded parameters from buck_params.m\n');
fprintf('Vin=%.3f V, Vout=%.3f V, L=%.3e H, C=%.3e F, Rload=%.3f ohm, Ts=%.3e s\n', ...
        Vin, Vout, L1, C1, Rload, Ts);

D0 = Vout / Vin;  
fprintf('Ideal averaged duty D0 = %.6f\n', D0);


A = [  0,          -1/L1;
      1/C1,   -1/(Rload*C1) ];

B = [ Vin / L1;
          0     ];

C = [0, 1];   % measure vC
D = 0;

sysc = ss(A,B,C,D);
fprintf('Continuous plant created. Continuous dcgain (d->v) = %.6f V per unit d\n', dcgain(sysc));

sysd = c2d(sysc, Ts, 'zoh');
fprintf('Discretized plant with Ts = %.3e s. Discrete dcgain = %.6f\n', Ts, dcgain(sysd));

n = size(sysd.A,1);
A_aug = [ sysd.A,        zeros(n,1);
          sysd.C,            1     ];
B_aug = [ sysd.B;
          0        ];
C_aug = [ sysd.C, 0 ];
D_aug = sysd.D;

sysd_aug = ss(A_aug, B_aug, C_aug, D_aug, Ts);

obs_rank = rank(obsv(sysd_aug.A, sysd_aug.C));
fprintf('Augmented plant states = %d, observability rank = %d\n', size(sysd_aug.A,1), obs_rank);

sysd_aug_red = minreal(sysd_aug);
fprintf('After minreal: reduced states = %d. dcgain (augmented reduced) = %.6f\n', ...
        size(sysd_aug_red.A,1), dcgain(sysd_aug_red));

Np = 40;   
Nc = 6;    

mpcobj = mpc(sysd_aug_red, Ts, Np, Nc);

mpcobj.Weights.OV = 1;        
mpcobj.Weights.MV = 0.15;     
mpcobj.Weights.MVRate = 5e-3; 


mpcobj.MV.Min = 0;
mpcobj.MV.Max = 1;
mpcobj.MV.RateMin = -0.05;
mpcobj.MV.RateMax = 0.05;

mpcobj.Model.Nominal.U = D0;
mpcobj.Model.Nominal.Y = Vout;

fprintf('Initial mpc object created. Internal plant states = %d\n', size(mpcobj.Model.Plant.A,1));

Iout_ss = Vout / Rload;
D_req = (Vout + Vd + Iout_ss * Ron) / Vin;
D_req = min(max(D_req, 0), 1);   % clip to [0,1]

fprintf('Estimated steady Iout = %.4f A\n', Iout_ss);
fprintf('Computed duty including Vd and Ron: D_req = %.6f\n', D_req);

if D_req < mpcobj.MV.Min || D_req > mpcobj.MV.Max
    warning('build_mpc:DutyOutOfBounds', ...
        'Computed steady duty D_req=%.6f is outside MV limits [%.3f, %.3f]. Adjust constraints.', ...
        D_req, mpcobj.MV.Min, mpcobj.MV.Max);
end

mpcobj.Model.Nominal.U = D_req;
mpcobj.Model.Nominal.Y = Vout;   

assignin('base','mpcobj',mpcobj);
fprintf('mpcobj exported to base workspace with Nominal.U = %.6f\n', mpcobj.Model.Nominal.U);



