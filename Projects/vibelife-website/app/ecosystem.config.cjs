module.exports = {
  apps: [
    {
      name: 'vibelife-dev',
      script: 'node_modules/vite/bin/vite.js',
      args: '--port 9182 --host',
      cwd: __dirname,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 2000,
      watch: false,
      env: {
        NODE_ENV: 'development',
      },
    },
  ],
};
