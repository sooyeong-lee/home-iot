'use strict';
/**
 * 기기 ID 규칙 · 등록 입력 검증 (DB·MQTT 없이 테스트할 수 있도록 index.js 에서 분리)
 */
const DEVICE_ID_RE = /^[a-z0-9][a-z0-9-]{2,49}$/;

/**
 * 기기 ID 자동 생성: <종류>-<사용자ID>-<순번 2자리>  예) light-5-01, light-5-02, aircon-5-01
 * existingIds: 같은 prefix 로 시작하는 기존 기기 ID 목록
 * 지금 있는 가장 큰 순번 + 1 (삭제된 번호는 다시 쓰지 않도록 최댓값 기준)
 */
function nextDeviceIdFrom(type, userId, existingIds) {
  const prefix = `${type}-${userId}-`;
  const max = existingIds.reduce((m, id) => {
    const n = Number.parseInt(id.slice(prefix.length), 10);
    return Number.isInteger(n) && n > m ? n : m;
  }, 0);
  return `${prefix}${String(max + 1).padStart(2, '0')}`;
}

/**
 * 기기 등록 입력 검증
 * @returns {{ auto: boolean, details: {field: string, message: string}[] }}
 *   auto = deviceId 를 보내지 않아 서버가 자동 생성해야 하는 경우
 */
function validateDeviceInput({ deviceId, name, type, location } = {}, deviceTypes) {
  const details = [];
  const auto = deviceId === undefined || deviceId === null || deviceId === '';
  if (!auto && (typeof deviceId !== 'string' || !DEVICE_ID_RE.test(deviceId))) details.push({ field: 'deviceId', message: '기기 ID는 소문자·숫자·하이픈 3~50자 (예: light-living-01)' });
  if (typeof name !== 'string' || !name.trim() || name.length > 100) details.push({ field: 'name', message: '기기 이름을 입력하세요 (100자 이하).' });
  if (!deviceTypes.includes(type)) details.push({ field: 'type', message: `기기 종류는 ${deviceTypes.join(', ')} 중 하나` });
  if (location !== undefined && location !== null && (typeof location !== 'string' || location.length > 50)) details.push({ field: 'location', message: '설치 위치는 50자 이하' });
  return { auto, details };
}

module.exports = { DEVICE_ID_RE, nextDeviceIdFrom, validateDeviceInput };
