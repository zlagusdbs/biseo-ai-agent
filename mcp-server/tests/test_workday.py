from kimbiseo.workday import compare

DAY = {"date": "2026-10-22", "start": "09:00", "end": "18:00", "hours": 8, "vacation": None}


def logs(*minutes):
    return {"totalSeconds": sum(minutes) * 60, "worklogs": [{"seconds": m * 60} for m in minutes]}


def test_short():
    r = compare("2026-10-22", DAY, logs(60, 330))
    assert r["status"] == "short" and r["gapMinutes"] == 90 and r["hr"]["minutes"] == 480 and r["worklog"]["minutes"] == 390


def test_match_and_over():
    assert compare("d", DAY, logs(480))["status"] == "match"
    assert compare("d", DAY, logs(500))["gapMinutes"] == -20


def test_day_off_counts_zero():
    r = compare("d", {"hours": 0, "vacation": 1}, logs())
    assert r["status"] == "match" and r["hr"]["dayOff"]


def test_unknown_when_one_side_missing():
    assert compare("d", None, logs(60))["status"] == "unknown"
    assert compare("d", DAY, None)["gapMinutes"] is None
