import type { CapacitorConfig } from '@capacitor/cli'

const config: CapacitorConfig = {
  appId: 'space.lysandra.quotakeeper',
  appName: '额度终端',
  webDir: 'dist',
  backgroundColor: '#05060c',
  android: {
    backgroundColor: '#05060c',
  },
  plugins: {
    LocalNotifications: {
      iconColor: '#ffde00',
    },
  },
}

export default config
