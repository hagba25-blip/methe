"""Traduit les erreurs métier levées par PostgreSQL en réponses HTTP lisibles."""

from contextlib import contextmanager

from fastapi import HTTPException, status
from psycopg import errors


@contextmanager
def business_errors():
    try:
        yield
    except errors.NoDataFound as e:          # SQLSTATE P0002
        raise HTTPException(status.HTTP_404_NOT_FOUND, e.diag.message_primary) from None
    except errors.RaiseException as e:       # SQLSTATE P0001
        raise HTTPException(status.HTTP_409_CONFLICT, e.diag.message_primary) from None
