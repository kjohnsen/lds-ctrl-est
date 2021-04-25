%%%
%%% This script fits a PLDS model to simulated data using subspace
%%% identification, then refines the fit using expectation-maximization.
%%%

%% create a simple second order model.
dt = 1e-3;
A = [0.95 -0.05; 0 0.9];
B = [0; 0.25];
C = eye(size(A));
n_x = size(A,1);
n_u = size(B,2);
n_y = size(C,1);
d = zeros(n_y,1) + log(0.01);%output bias

% process noise covariance
Q = 1e-4 * eye(n_x);

% initial conditions
x0 = zeros(n_x,1);%expected initial state
P0 = Q;%covariance about that state

% process disturbance, input gain, etc.
m = zeros(n_x,1);
g = ones(n_u,1);

%     PLDS(dt,A,B,g,m,Q,C,d,x0,P0)
sys = PLDS(dt,A,B,g,m,Q,C,d,x0,P0);

%% simulate forward and generate training data
rng(13)%for reproducibility

dt = 1e-3;
T = 10;
n_trials = 15;

t = 0:dt:5;
n_samp = length(t);

u = repmat({zeros(n_u, n_samp)}, [n_trials, 1]);

% making the input some random data.
for trial=1:n_trials
  for k=2:n_samp
    u{trial}(:,k) = 0.975*u{trial}(:,k-1) + 1e-1*randn(n_u,1);
  end
end

[y, x, z] = sys.simulate(u,true);

n_samp_imp = ceil(0.1/dt);
y_imp = sys.simulate_imp(n_samp_imp);

%% fit model
sys_hat = copy(sys);
n_x_fit = n_x;
n_h = 50;
tic()
sing_vals = plds_ssid_mex(sys_hat, u, z, dt, n_x_fit, n_h, d);
toc()

%% compare fit to original
[y_hat, x_hat] = sys_hat.simulate(u,false);
% [y_hat, x_hat] = sys_hat.ppfilter_joint(u,z);
[y_imp_hat, t_imp] = sys_hat.simulate_imp(n_samp_imp);

figure;
subplot(121);
semilogy(sing_vals(1:n_h), '-o', 'color', 0.5+zeros(1,3)); hold on;
semilogy(sing_vals(1:n_x_fit), 'color', 'k', 'linewidth', 2);
ylabel('Singular Values')
xlabel('Singular Value Index')

subplot(122); hold on;
plot(t_imp, y_imp{1}, '-', 'color', [0 0 0], 'linewidth', 2);
plot(t_imp, y_imp_hat{1}, '-', 'color', [0 0 0]+0.5, 'linewidth', 2);
legend('ground truth', 'estimated')
ylabel('Impulse Response (a.u.)')
xlabel('Time (s)')

z_m = cell2mat(z');
y_hat_m = cell2mat(y_hat');
pve = 1 - var(z_m-y_hat_m,[],2)./var(z_m,[],2);

eg_trial = 1;

figure;
subplot(311); hold on;
h=plot(t, y{eg_trial}(1,:)'/dt, '-', 'color', zeros(1,3));
h(2)=plot(t, y_hat{eg_trial}(1,:)'/dt, '-', 'color', 0.5+zeros(1,3), 'linewidth', 2);
legend(h, 'measurement', 'fit')
ylabel('Output 1 (events/s)')
xlabel('Time (s)')
title(['proportion var explained (training): ' num2str(pve(1))])

subplot(312); hold on;
plot(t, y{eg_trial}(2,:)'/dt, '-', 'color', zeros(1,3));
plot(t, y_hat{eg_trial}(2,:)'/dt, '-', 'color', 0.5+zeros(1,3), 'linewidth', 2);
ylabel('Output 2 (events/s)')
xlabel('Time (s)')
title(['proportion var explained (training): ' num2str(pve(2))])

subplot(313)
plot(t, u{eg_trial}','color', zeros(1,3));
ylabel('Input (a.u.)')
xlabel('Time (s)')

%% Refit by E-M
do_refit = true;
if (do_refit)
  calcAB = true; %calculate dynamics (A, B mats)
  calcQ = true; %calculate process noise cov (Q)
  calcInitial = true; %calculate initial conditions
  calcOutput = true; %calculate output (C)
  calcMeasurement = true; %calculate output noise (R)
  n_iter = 500;
  tol = 1e-2;

  [y_em, x_em, sum_E_xu_tm1_xu_tm1, sum_E_xu_t_xu_tm1, sum_E_x_t_x_t, n_t] = plds_em_refit_mex(sys_hat, u, z, calcAB, calcQ, calcInitial, calcOutput, calcMeasurement, n_iter, tol);

  % [y_hat_em, x_hat_em] = sys_hat.ppfilter_joint(u,z);
  [y_hat_em, x_hat_em] = sys_hat.simulate(u,false);
  y_imp_hat_em = sys_hat.simulate_imp(n_samp_imp);

  % E-M smoothed estimates
  figure;
  subplot(311); hold on;
  plot(t, y{eg_trial}(1,:)/dt,'color', zeros(1,3));
  plot(t, y_em{eg_trial}(1,:)/dt,'color', [0 0 0]+0.5, 'linewidth', 2);
  legend('ground truth', 'E-M re-estimated')
  ylabel('Output (events/s)')

  subplot(312);
  plot(t, z{eg_trial}(1,:),'color', zeros(1,3));

  subplot(313)
  plot(t, u{eg_trial}','color', zeros(1,3));
  ylabel('Input (a.u.)')
  xlabel('Time (s)')

  figure;
  subplot(122); hold on;
  plot(t_imp, y_imp{1}, '-', 'color', [0 0 0], 'linewidth', 2);
  plot(t_imp, y_imp_hat_em{1}, '-', 'color', [0 0 0]+0.5, 'linewidth', 2);
  legend('ground truth', 'EM re-estimated')
  ylabel('Impulse Response (a.u.)')
  xlabel('Time (s)')

  y_hat_em_m = cell2mat(y_hat_em');
  pve_em = 1 - var(z_m-y_hat_em_m,[],2)./var(z_m,[],2);

  figure;
  subplot(311); hold on;
  h=plot(t, y{eg_trial}(1,:)'/dt, '-', 'color', zeros(1,3));
  h(2)=plot(t, y_hat_em{eg_trial}(1,:)'/dt, '-', 'color', 0.5+zeros(1,3), 'linewidth', 2);
  legend(h, 'measurement', 'fit')
  ylabel('Output 1 (a.u.)')
  xlabel('Time (s)')
  title(['EM-refit proportion var explained (training): ' num2str(pve_em(1))])

  subplot(312); hold on;
  plot(t, y{eg_trial}(2,:)'/dt, '-', 'color', zeros(1,3));
  plot(t, y_hat_em{eg_trial}(2,:)'/dt, '-', 'color', 0.5+zeros(1,3), 'linewidth', 2);
  ylabel('Output 2 (a.u.)')
  xlabel('Time (s)')
  title(['EM-refit proportion var explained (training): ' num2str(pve_em(2))])

  subplot(313)
  plot(t, u{eg_trial}','color', zeros(1,3));
  ylabel('Input (a.u.)')
  xlabel('Time (s)')
end
