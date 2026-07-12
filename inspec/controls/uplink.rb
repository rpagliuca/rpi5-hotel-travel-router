control 'uplink-01' do
  impact 1.0
  title 'WiFi uplink client is running'
  desc 'wpa_supplicant@wlan0 must be active for the hotel WiFi connection'

  describe service('wpa_supplicant@wlan0') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'uplink-02' do
  impact 0.8
  title 'NetworkManager does not manage the radio'
  desc 'wlan0/uap0 must be listed as unmanaged so NM does not fight over them'

  describe file('/etc/NetworkManager/conf.d/99-travel-router-unmanaged.conf') do
    it { should exist }
    its('content') { should match(/unmanaged-devices=.*wlan0.*uap0/) }
  end
end

control 'uplink-03' do
  impact 0.9
  title 'Uplink has connectivity'
  desc 'wlan0 (or eth0 fallback) must be able to reach the internet'

  describe command('curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://1.1.1.1') do
    its('stdout') { should match(/^(200|301|302)$/) }
  end
end
