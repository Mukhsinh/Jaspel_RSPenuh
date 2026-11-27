module.exports = {
  apps: [
    {
      name: 'jaspel-app',
      cwd: __dirname,
      script: 'node_modules/next/dist/bin/next',
      args: 'start -H 0.0.0.0',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      env: {
        NODE_ENV: 'production',
        PORT: process.env.PORT || 3000,
        HOSTNAME: '0.0.0.0',
      },
    },
  ],
};
