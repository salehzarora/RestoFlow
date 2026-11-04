/** @type {import('next').NextConfig} */
const nextConfig = {
  images: { unoptimized: true },
  reactStrictMode: true,
  poweredByHeader: false,
  trailingSlash: false,
  expireTime: 360,
  // Group styles by route use instead of shipping every screen everywhere.
  // A modest request cost balances stylesheet requests with unrelated bytes.
  experimental: { cssChunking: { type: 'graph', requestCost: 5000 } },
};

export default nextConfig;
