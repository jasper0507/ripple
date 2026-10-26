-- Idempotent initial communities; never reset existing content or IDs.
INSERT INTO communities (name, introduction, created_at, updated_at) VALUES
  ('开发讨论', '交流开发经验与技术问题', NOW(), NOW()),
  ('技术分享', '分享技术文章与实践心得', NOW(), NOW()),
  ('问答交流', '提出问题并分享解答', NOW(), NOW()),
  ('项目实践', '展示项目与讨论实现', NOW(), NOW()),
  ('日常讨论', '聊聊开发之外的话题', NOW(), NOW())
ON DUPLICATE KEY UPDATE name = communities.name;
