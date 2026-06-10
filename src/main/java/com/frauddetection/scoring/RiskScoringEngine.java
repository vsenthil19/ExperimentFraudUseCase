package com.frauddetection.scoring;

import com.frauddetection.model.BeneficiaryStatus;
import com.frauddetection.model.CustomerProfile;
import com.frauddetection.model.FasterPaymentRequest;
import com.frauddetection.model.RiskAssessment;
import com.frauddetection.model.RiskFactor;

import java.util.ArrayList;
import java.util.List;

/**
 * Composes AmountScorer, CopScorer, BehaviouralScorer, and ChannelScorer
 * to produce a composite RiskAssessment.
 *
 * <p>Each component scorer contributes a score in [0, 25]. The composite
 * riskScore is the sum of all four, giving a range of [0, 100].
 *
 * <p>Risk factors are collected from any scorer that returns a non-zero score.
 */
public class RiskScoringEngine {

    private final AmountScorer amountScorer;
    private final CopScorer copScorer;
    private final BehaviouralScorer behaviouralScorer;
    private final ChannelScorer channelScorer;

    public RiskScoringEngine(AmountScorer amountScorer,
                             CopScorer copScorer,
                             BehaviouralScorer behaviouralScorer,
                             ChannelScorer channelScorer) {
        this.amountScorer = amountScorer;
        this.copScorer = copScorer;
        this.behaviouralScorer = behaviouralScorer;
        this.channelScorer = channelScorer;
    }

    /**
     * Scores a payment request by invoking each component scorer and aggregating results.
     *
     * @param request            the faster payment request to evaluate
     * @param profile            the debtor's customer profile
     * @param beneficiaryStatus  the beneficiary status (reserved for future use)
     * @return a RiskAssessment containing composite and individual scores plus risk factors
     */
    public RiskAssessment score(FasterPaymentRequest request,
                                CustomerProfile profile,
                                BeneficiaryStatus beneficiaryStatus) {

        ScorerResult amountResult = amountScorer.score(request, profile);
        ScorerResult copResult = copScorer.score(request, profile);
        ScorerResult behaviouralResult = behaviouralScorer.score(request, profile);
        ScorerResult channelResult = channelScorer.score(request, profile);

        int compositeScore = amountResult.score()
                + copResult.score()
                + behaviouralResult.score()
                + channelResult.score();

        List<RiskFactor> riskFactors = new ArrayList<>();

        if (amountResult.score() > 0) {
            riskFactors.add(new RiskFactor("amount", amountResult.explanation()));
        }
        if (copResult.score() > 0) {
            riskFactors.add(new RiskFactor("cop", copResult.explanation()));
        }
        if (behaviouralResult.score() > 0) {
            riskFactors.add(new RiskFactor("behavioural", behaviouralResult.explanation()));
        }
        if (channelResult.score() > 0) {
            riskFactors.add(new RiskFactor("channel", channelResult.explanation()));
        }

        return new RiskAssessment(
                compositeScore,
                amountResult.score(),
                copResult.score(),
                behaviouralResult.score(),
                channelResult.score(),
                riskFactors
        );
    }
}
