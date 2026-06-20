import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}', './lib/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#06111f',
        panel: '#0b1728',
        line: 'rgba(148,163,184,0.16)',
        cyanGlow: '#22d3ee',
      },
      boxShadow: {
        glow: '0 0 40px rgba(34, 211, 238, 0.18)',
      },
    },
  },
  plugins: [],
};

export default config;
