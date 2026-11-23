'use strict';
/**
 * 엘리베이터 층 이동 규칙 (MQTT 없이 테스트할 수 있도록 index.js 에서 분리)
 */

/** 목표 층으로 한 층 이동한 다음 층. 0층은 없으므로 건너뛴다. 이미 도착했으면 현재 층 그대로 */
function nextFloor(current, target) {
  if (current === target) return current;
  const step = target > current ? 1 : -1;
  let next = current + step;
  if (next === 0) next += step;
  return next;
}

module.exports = { nextFloor };
