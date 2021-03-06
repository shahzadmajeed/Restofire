//
//  RequestOperation.swift
//  Restofire
//
//  Created by Rahul Katariya on 28/01/18.
//  Copyright © 2018 Restofire. All rights reserved.
//

import Foundation
import Alamofire

/// An NSOperation that executes the `Requestable` asynchronously.
public class RequestOperation<R: Requestable>: NetworkOperation<R> {
    let requestable: R
    let dataRequest: () -> DataRequest
    let completionQueue: DispatchQueue
    let completionHandler: ((DataResponse<R.Response>) -> Void)?

    /// Intializes an request operation.
    ///
    /// - Parameters:
    ///   - requestable: The `Requestable`.
    ///   - request: The request closure.
    ///   - completionHandler: The async completion handler called
    ///     when the request is completed
    public init(
        requestable: R,
        request: @escaping () -> DataRequest,
        downloadProgressHandler: ((Progress) -> Void, queue: DispatchQueue?)? = nil,
        completionQueue: DispatchQueue,
        completionHandler: ((DataResponse<R.Response>) -> Void)?
    ) {
        self.requestable = requestable
        self.dataRequest = request
        self.completionQueue = completionQueue
        self.completionHandler = completionHandler
        super.init(
            requestable: requestable,
            request: request,
            downloadProgressHandler: downloadProgressHandler
        )
    }

    override func handleDataResponse(_ response: DataResponse<R.Response>) {
        let request = self.request as! DataRequest

        var res = response
        requestable.delegates.forEach {
            res = $0.process(request, requestable: requestable, response: res)
        }
        res = requestable.process(request, requestable: requestable, response: res)

        completionQueue.async {
            self.completionHandler?(res)
        }

        switch res.result {
        case .success(let value):
            self.requestable.request(self, didCompleteWithValue: value)
        case .failure(let error):
            self.requestable.request(self, didFailWithError: error)
        }

        self.isFinished = true
    }

    override func dataResponseResult(response: DataResponse<Data?>) -> DataResponse<R.Response> {
        let result = Result<R.Response, RFError>.serialize { try requestable.responseSerializer
            .serialize(
                request: response.request,
                response: response.response,
                data: response.data,
                error: response.error
            )
        }

        var responseResult: RFResult<R.Response>!

        switch result {
        case .success(let value):
            responseResult = value
        case .failure(let error):
            assertionFailure(error.localizedDescription)
            responseResult = RFResult<R.Response>.failure(error)
        }

        let dataResponse = DataResponse<R.Response>(
            request: response.request,
            response: response.response,
            data: response.data,
            metrics: response.metrics,
            serializationDuration: response.serializationDuration,
            result: responseResult
        )
        return dataResponse
    }

    /// Creates a copy of self
    open override func copy() -> NetworkOperation<R> {
        let operation = RequestOperation(
            requestable: requestable,
            request: dataRequest,
            completionQueue: completionQueue,
            completionHandler: completionHandler
        )
        return operation
    }
}
