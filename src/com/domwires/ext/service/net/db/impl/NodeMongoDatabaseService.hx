package com.domwires.ext.service.net.db.impl;

import js.npm.mongodb.MongoCursor;
import js.lib.Error;
import js.lib.Promise;
import js.npm.mongodb.MongoClient;
import js.npm.mongodb.MongoCollection;
import js.npm.mongodb.MongoDatabase;

@await class NodeMongoDatabaseService extends AbstractService implements IDataBaseService
{
    @Inject("IDataBaseService_enabled")
    @Optional
    private var __enabled:Bool;

    @Inject("IDataBaseService_uri")
    private var _uri:String;

    @Inject("IDataBaseService_dataBaseName")
    private var _dataBaseName:String;

    public var isConnected(get, never):Bool;
    private var _isConnected:Bool;

    private var database:MongoDatabase;

    private var collectionMap:Map<String, MongoCollection> = [];

    private var result:Dynamic;
    private var error:MongoError;

    override private function init():Void
    {
        initResult(__enabled);
    }

    override private function checkEnabled():Bool
    {
        var enabled:Bool = super.checkEnabled();

        if (enabled)
        {
            if (!_isConnected)
            {
                trace("Not connected to database: " + _uri);

                return false;
            }
        }

        return true;
    }

    public function connect():IDataBaseService
    {
        if (!super.checkEnabled())
        {
            return this;
        }
        if (_isConnected)
        {
            trace("Already connected to database: " + _uri);

            return this;
        }

        MongoClient.connect(_uri, null, handleConnect);

        return this;
    }

    public function disconnect():IDataBaseService
    {
        if (!checkEnabled())
        {
            return this;
        }

        if (database != null)
        {
            database.close(true, handleDisconnect);
        } else
        {
            handleDisconnect();
        }

        return this;
    }

    private function handleDisconnect(?error:Error, ?data:Dynamic):Void
    {
        trace("Disconnected: Error: " + error + "; Data: " + data);

        collectionMap.clear();

        _isConnected = false;

        dispatchMessage(DataBaseServiceMessageType.Disconnected);
    }

    private function handleConnect(error:Error, database:MongoDatabase):Void
    {
        if (error != null)
        {
            trace("Connection error: " + error);

            dispatchMessage(DataBaseServiceMessageType.ConnectError);
        } else
        {
            trace("Connected!");

            _isConnected = true;

            this.database = database.db(_dataBaseName);

            dispatchMessage(DataBaseServiceMessageType.Connected);
        }
    }

    private function checkBeforeQuery():Bool
    {
        if (!checkEnabled()) return false;

        result = null;
        error = null;

        return true;
    }

    public function insert(tableName:String, itemList:Array<Dynamic>):IDataBaseService
    {
        if (!checkBeforeQuery() || itemList.length == 0) return this;

        var collection:MongoCollection = this.collection(tableName);
        var promise:Promise<Dynamic> = itemList.length == 1 ?
            collection.insertOne(itemList[0]) : collection.insertMany(itemList);

        promise.then(result -> {
            this.result = result;
            handleInsertResult();
            dispatchMessage(DataBaseServiceMessageType.InsertResult);
        }).catchError((error:MongoError) -> {
            this.error = error;
            handleInsertError();
            dispatchMessage(DataBaseServiceMessageType.InsertError);
        });

        return this;
    }

    public function find(tableName:String, filter:Dynamic, maxCount:UInt = 1):IDataBaseService
    {
        if (!checkBeforeQuery() || maxCount == 0) return this;

        var collection:MongoCollection = this.collection(tableName);

        if (maxCount == 1)
        {
            var promise:Promise<Dynamic> = collection.findOne(filter);
            promise.then(findSuccess).catchError(findError);
        } else
        {
            var cursor:MongoCursor = cast collection.find(filter);
            cursor.limit(maxCount);
            cursor.toArray(findManyResult);
        }

        return this;
    }

    public function update(tableName:String, filter:Dynamic, setParams:Dynamic, single:Bool = true):IDataBaseService
    {
        if (!checkBeforeQuery()) return this;

        var collection:MongoCollection = this.collection(tableName);
        var promise:Promise<Dynamic>;

        if (single)
        {
            promise = collection.updateOne(filter, {$set: setParams});
            promise.then(updateSuccess).catchError(updateError);
        } else
        {
            promise = collection.updateMany(filter, {$set: setParams});
            promise.then(updateSuccess).catchError(updateError);
        }

        return this;
    }

    private function updateSuccess(result:Dynamic):Void
    {
        this.result = result;
        handleUpdateResult();
        dispatchMessage(DataBaseServiceMessageType.UpdateResult);
    }

    private function updateError(error:MongoError):Void
    {
        this.error = error;
        handleUpdateError();
        dispatchMessage(DataBaseServiceMessageType.UpdateError);
    }

    private function handleUpdateResult():Void
    {

    }

    private function handleUpdateError():Void
    {

    }

    public function delete(tableName:String, filter:Dynamic, single:Bool = true):IDataBaseService
    {
        if (!checkBeforeQuery()) return this;

        var collection:MongoCollection = this.collection(tableName);
        var promise:Promise<Dynamic>;

        if (single)
        {
            promise = collection.deleteOne(filter);
            promise.then(deleteSuccess).catchError(deleteError);
        } else
        {
            promise = collection.deleteMany(filter);
            promise.then(deleteSuccess).catchError(deleteError);
        }

        return this;
    }

    private function deleteSuccess(result:Dynamic):Void
    {
        this.result = result;
        handleDeleteResult();
        dispatchMessage(DataBaseServiceMessageType.DeleteResult);
    }

    private function deleteError(error:MongoError):Void
    {
        this.error = error;
        handleDeleteError();
        dispatchMessage(DataBaseServiceMessageType.DeleteError);
    }

    private function handleDeleteResult():Void
    {

    }

    private function handleDeleteError():Void
    {

    }

    public function createTable(name:String, ?uniqueIndexList:Array<String>):IDataBaseService
    {
        if (!checkBeforeQuery()) return this;

        database.createCollection(name, (error:Error, resultCollection:MongoCollection) -> {
            if (error != null)
            {
                throw error;
            }

            if (uniqueIndexList != null && uniqueIndexList.length > 0)
            {
                var indexData:Dynamic = {};
                for (indexName in uniqueIndexList)
                {
                    Reflect.setField(indexData, indexName, 1);
                }
                var promise:Promise<Dynamic> = resultCollection.createIndex(indexData, {unique: true});
                promise.then(indexName -> {
                    createTableSuccess(result);
                }).catchError(e -> {
                    trace("pizdec");
                });
            } else
            {
                createTableSuccess(result);
            }
        });

        return this;
    }

    private function createTableSuccess(result:Dynamic):Void
    {
        this.result = result;
        handleCreateTableResult();
        dispatchMessage(DataBaseServiceMessageType.CreateTableResult);
    }

    private function handleCreateTableResult():Void
    {

    }

    public function dropTable(tableName:String):IDataBaseService
    {
        if (!checkBeforeQuery()) return this;

        var collection:MongoCollection = this.collection(tableName);
        collection.drop(dropTableResult);
        
        return this;
    }

    private function dropTableResult(error:MongoError, result:Dynamic):Void
    {
        this.result = result;
        this.error = error;

        if (result != null)
        {
            this.result = result;
            handleDropTableResult();
            dispatchMessage(DataBaseServiceMessageType.DropTableResult);
        } else
        {
            this.error = error;
            handleDropTableError();
            dispatchMessage(DataBaseServiceMessageType.DropTableError);
        }
    }

    private function handleDropTableResult():Void
    {

    }

    private function handleDropTableError():Void
    {

    }

    private function findManyResult(error:MongoError, result:Dynamic):Void
    {
        if (result != null)
        {
            findSuccess(result);
        } else
        {
            findError(error);
        }
    }

    private function findSuccess(result:Dynamic):Void
    {
        this.result = result;
        handleFindResult();
        dispatchMessage(DataBaseServiceMessageType.FindResult);
    }

    private function findError(error:MongoError):Void
    {
        this.error = error;
        handleFindError();
        dispatchMessage(DataBaseServiceMessageType.FindError);
    }

    private function handleInsertResult():Void
    {

    }

    private function handleInsertError():Void
    {

    }

    private function handleFindResult():Void
    {

    }

    private function handleFindError():Void
    {

    }

    private function collection(name:String):MongoCollection
    {
        if (!checkEnabled()) return null;

        if (!collectionMap.exists(name))
        {
            collectionMap.set(name, database.collection(name));
        }

        return collectionMap.get(name);
    }

    private function get_isConnected():Bool
    {
        return _isConnected;
    }
}

typedef MongoError = {
    code:Int,
    errmsg:String,
    message:String,
    stack:String
}

enum abstract MongoErrorCode(Int)
{
    var Duplicate = 11000;
}