const DASHSCOPE_BUCKET =
  'dashscope-[a-z0-9](?:[a-z0-9-]{0,51}[a-z0-9])?';
const OSS_REGION = 'oss-cn-[a-z0-9](?:[a-z0-9-]{0,54}[a-z0-9])?';
const ALIBABA_RESULT_HOST = new RegExp(
  `^${DASHSCOPE_BUCKET}\\.(?:oss-accelerate|${OSS_REGION})\\.aliyuncs\\.com$`,
);

/** Matches only the dynamic DashScope OSS result-host formats documented by Alibaba. */
export function isAllowedAlibabaResultHost(hostname) {
  return (
    typeof hostname === 'string' &&
    ALIBABA_RESULT_HOST.test(hostname.toLowerCase())
  );
}
