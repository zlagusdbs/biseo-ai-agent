"""하루 맞춰 보기: HR 유연근무 시간과 Jira worklog 합계를 비교한다 (Worklogcal 는 worklog 기준으로 보여 준다)."""


def compare(date: str, hr_day: dict | None, worklogs: dict | None) -> dict:
    """hr_day: flexwork_week 의 하루 (없으면 None). worklogs: JiraClient.my_worklogs 결과 (없으면 None).

    gapMinutes = HR 근무 시간 - worklog 합계. 양수면 덜 기록, 음수면 더 기록.
    """
    planned = None
    if hr_day is not None:
        planned = 0 if hr_day.get("vacation") else int(round(float(hr_day.get("hours") or 0) * 60))
    logged = None if worklogs is None else int(worklogs.get("totalSeconds", 0)) // 60
    if planned is None or logged is None:
        status, gap = "unknown", None
    else:
        gap = planned - logged
        status = "match" if gap == 0 else ("short" if gap > 0 else "over")
    return {
        "date": date,
        "hr": None if hr_day is None else {"start": hr_day.get("start"), "end": hr_day.get("end"),
                                             "minutes": planned, "dayOff": bool(hr_day.get("vacation"))},
        "worklog": None if worklogs is None else {"minutes": logged, "items": worklogs.get("worklogs", [])},
        "gapMinutes": gap,
        "status": status,
    }
