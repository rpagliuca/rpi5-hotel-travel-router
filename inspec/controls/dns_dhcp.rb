control 'dns-dhcp-01' do
  impact 1.0
  title 'dnsmasq service is running'

  describe service('dnsmasq') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'dns-dhcp-02' do
  impact 0.9
  title 'dnsmasq config file exists for uap0'

  describe file('/etc/dnsmasq.d/uap0.conf') do
    it { should exist }
    its('content') { should match(/^interface=uap0/) }
    its('content') { should match(/^dhcp-range=/) }
  end
end

control 'dns-dhcp-03' do
  impact 0.8
  title 'dnsmasq is listening on uap0'

  describe port(53) do
    it { should be_listening }
  end

  describe port(67) do
    it { should be_listening }
    its('protocols') { should include 'udp' }
  end
end
