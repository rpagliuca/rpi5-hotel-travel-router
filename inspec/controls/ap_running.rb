control 'ap-01' do
  impact 1.0
  title 'Access Point is running'
  desc 'hostapd must be active and the uap0 interface must be up'

  describe service('hostapd') do
    it { should be_enabled }
    it { should be_running }
  end

  describe interface('uap0') do
    it { should exist }
    it { should be_up }
  end
end

control 'ap-02' do
  impact 0.9
  title 'AP interface has correct IP address'
  desc 'uap0 must have the configured AP subnet IP'

  describe interface('uap0') do
    its('ipv4_addresses') { should include '192.168.88.1' }
  end
end

control 'ap-03' do
  impact 0.9
  title 'AP interface is broadcasting SSID'
  desc 'hostapd config must reference uap0'

  describe file('/etc/hostapd/hostapd.conf') do
    it { should exist }
    its('content') { should match(/^interface=uap0/) }
    its('content') { should match(/^ssid=/) }
    its('content') { should match(/^wpa=2/) }
  end
end
