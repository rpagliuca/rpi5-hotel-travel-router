control 'tailscale-01' do
  impact 1.0
  title 'tailscaled service is running'

  describe service('tailscaled') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'tailscale-02' do
  impact 1.0
  title 'Tailscale is authenticated and connected'
  desc 'tailscale status must show the node is logged in and not expired'

  describe command('tailscale status --json') do
    its('exit_status') { should eq 0 }
    its('stdout') { should match(/"BackendState"\s*:\s*"Running"/) }
  end
end

control 'tailscale-03' do
  impact 0.9
  title 'Tailscale interface exists'

  describe interface('tailscale0') do
    it { should exist }
    it { should be_up }
  end
end

control 'tailscale-04' do
  impact 1.0
  title 'Exit node is configured'
  desc 'tailscale status must show an exit node is in use'

  describe command('tailscale status --json') do
    its('stdout') { should match(/"ExitNodeStatus"/) }
  end
end
