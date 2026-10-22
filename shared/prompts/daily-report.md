오늘 아침 업무 보고를 해줘.

jira_search 도구로 내 미완료 이슈를 조회해(JQL: assignee = currentUser() AND statusCategory != Done ORDER BY duedate ASC, priority DESC).

형식:
- 첫 줄은 정확히 "미완료 Jira N건" (N 은 total).
- 다음 줄부터 기한이 지났거나 오늘·내일인 이슈를 먼저, 그다음 우선순위 순으로 한 줄씩: 이슈 키 · 제목 · 상태 · 기한.
- truncated 가 true 면 마지막 줄에 "전체 N건 중 일부만 보여요".
- 도구 결과에 error 가 있으면 첫 줄에 그 코드를 쓰고 할 일을 안내한다.
