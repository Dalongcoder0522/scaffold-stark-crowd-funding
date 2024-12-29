/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  images: {
    // make sure no one injects anything funny in svg
    dangerouslyAllowSVG: true,
    remotePatterns: [
      // we might need to add more links. this is just from the starknet ID identicon
      {
        protocol: "https",
        hostname: "identicon.starknet.id",
        pathname: "/**", // Allows all paths under this domain
      },
      {
        protocol: "https",
        hostname: "img.starkurabu.com",
        pathname: "/**",
      },
    ],
  },
  typescript: {
    ignoreBuildErrors: process.env.NEXT_PUBLIC_IGNORE_BUILD_ERROR === "true",
  },
  eslint: {
    ignoreDuringBuilds: process.env.NEXT_PUBLIC_IGNORE_BUILD_ERROR === "true",
  },
  webpack: (config, { isServer }) => {
    if (!isServer) {
      config.resolve.fallback = {
        fs: false,
        net: false,
        tls: false,
        url: false,
        crypto: false,
        stream: false,
        path: false,
        http: false,
        https: false,
        zlib: false,
        querystring: false,
        buffer: false,
      };

      // Add a rule to handle node: protocol imports
      config.module.rules.push({
        test: /[\\/]node_modules[\\/]tough-cookie[\\/].*\.js$/,
        use: {
          loader: 'babel-loader',
          options: {
            presets: ['@babel/preset-env'],
            plugins: [
              ['module-resolver', {
                alias: {
                  'node:url': 'url',
                  'node:punycode': 'punycode',
                  'node:net': false,
                }
              }]
            ]
          }
        }
      });
    }
    config.externals.push("pino-pretty", "lokijs", "encoding");
    return config;
  },
};

export default nextConfig;
