# pylint: disable=import-outside-toplevel

from typing import Optional, Callable, IO

from unified_planning.engines import Engine, Credits
from unified_planning.engines.mixins import OneshotPlannerMixin, PlanValidatorMixin
from unified_planning.model import ProblemKind


def _on_import_error(e: ImportError) -> ImportError:
    import os

    current_dir = os.path.dirname(__file__)
    return ImportError(
        f"NextFLAP implementation not found. Error: {e}\n\n"
        "To install NextFLAP:\n"
        f"   bash {current_dir}/install.sh\n\n"
        "Note: Building NextFLAP requires system dependencies (g++, libz3-dev)."
    )


class NextFLAPPlanner(Engine, OneshotPlannerMixin, PlanValidatorMixin):
    """
    NextFLAP planner wrapper for Tyr framework.

    NextFLAP is an expressive temporal and numeric planner supporting planning problems
    involving Boolean and numeric state variables, instantaneous and durative actions.
    """

    def __init__(self, **kwargs):
        Engine.__init__(self)
        OneshotPlannerMixin.__init__(self)
        PlanValidatorMixin.__init__(self)
        # Try to import and use the NextFLAP implementation
        try:
            from up_nextflap import NextFLAPImpl

            self._nextflap_engine = NextFLAPImpl(**kwargs)
        except ImportError as e:
            raise _on_import_error(e) from e

    @property
    def name(self) -> str:
        return "nextflap"

    @staticmethod
    def supported_kind() -> ProblemKind:
        """Return the supported problem kind for NextFLAP."""
        try:
            from up_nextflap import NextFLAPImpl

            return NextFLAPImpl.supported_kind()
        except ImportError as e:
            raise _on_import_error(e) from e

    @staticmethod
    def supports(problem_kind: ProblemKind) -> bool:
        """Check if NextFLAP supports the given problem kind."""
        return problem_kind <= NextFLAPPlanner.supported_kind()

    @staticmethod
    def supports_plan(plan_kind) -> bool:
        """Check if NextFLAP supports the given plan kind."""
        try:
            from up_nextflap import NextFLAPImpl

            return NextFLAPImpl.supports_plan(plan_kind)
        except ImportError as e:
            raise _on_import_error(e) from e

    @staticmethod
    def get_credits(**kwargs) -> Optional[Credits]:
        """Get credits for NextFLAP."""
        try:
            from up_nextflap import NextFLAPImpl

            return NextFLAPImpl.get_credits(**kwargs)
        except ImportError as e:
            raise _on_import_error(e) from e

    def _solve(
        self,
        problem: "up.model.Problem",
        callback: Optional[Callable[["up.engines.PlanGenerationResult"], None]] = None,
        timeout: Optional[float] = None,
        output_stream: Optional[IO[str]] = None,
    ) -> "up.engines.results.PlanGenerationResult":
        """Solve the planning problem using NextFLAP."""
        if hasattr(self, "_nextflap_engine"):
            return self._nextflap_engine._solve(
                problem,
                callback,
                timeout,
                output_stream,
            )
        raise RuntimeError("NextFLAP engine not properly initialized")

    def _validate(
        self, problem: "up.model.AbstractProblem", plan: "up.plans.Plan"
    ) -> "up.engines.results.ValidationResult":
        """Validate a plan using NextFLAP."""
        if hasattr(self, "_nextflap_engine"):
            return self._nextflap_engine._validate(problem, plan)
        raise RuntimeError("NextFLAP engine not properly initialized")

    def destroy(self):
        """Clean up the NextFLAP engine."""
        if hasattr(self, "_nextflap_engine"):
            self._nextflap_engine.destroy()


__all__ = ["NextFLAPPlanner"]
