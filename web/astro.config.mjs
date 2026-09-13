import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://pulse.l.cd',
  output: 'static',
  build: {
    format: 'directory'
  }
});
