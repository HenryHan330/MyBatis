# 10 MP 条件构造器与 IService

> 本篇是 MP 的**核心战斗力**：`Wrapper` 负责「条件」，`IService` 负责「业务层」。
> 学完这一篇，单表业务基本一行 SQL 都不用写。

## 1. Wrapper 的继承体系

```text
Wrapper<T>（抽象类）
└── AbstractWrapper<T, R, Children>        ← 提供 eq/like/gt/in/orderBy… 所有条件方法
    ├── QueryWrapper<T>            普通条件构造器（字符串列名）
    ├── UpdateWrapper<T>           带 set 能力的条件构造器（字符串列名）
    ├── LambdaQueryWrapper<T>      方法引用版 QueryWrapper（推荐）
    └── LambdaUpdateWrapper<T>     方法引用版 UpdateWrapper（推荐）
```

- `QueryWrapper` / `LambdaQueryWrapper`：用于 **select / delete / update 的 where 条件**。
- `UpdateWrapper` / `LambdaUpdateWrapper`：**当 `set` 子句比较特殊时**（如 `price = price + 5`、把字段置 null）使用。

> 官方提示：`QueryWrapper` / `LambdaQueryWrapper` **只适合单表**。多表连接请写 MyBatis XML
> —— MP 也能做多表，但代码会变得很难维护、很难读。

## 2. `QueryWrapper`

**需求**：查询品牌中带「宝」、厂商指导价 > 20 万的车，只要 `id`、`car_num`、`brand`、`guide_price`。

SQL 写法：

```sql
select id, car_num, brand, guide_price from t_car
where brand like '%宝%' and guide_price > 20;
```

```java
@Test
void testQueryWrapper() {
    // 1. 创建条件构造器
    QueryWrapper<Car> wrapper = new QueryWrapper<>();
    // 2. 链式追加条件
    wrapper.select("id", "car_num", "brand", "guide_price")
           .like("brand", "宝")
           .gt("guide_price", 20.0);
    // 3. 查询
    List<Car> cars = carMapper.selectList(wrapper);
    cars.forEach(System.out::println);
}
```

**问题**：`"brand"`、`"guide_price"` 全是**硬编码字符串** —— 列名改了、字符串写错了，
编译器都不会报错，只有运行期才炸。于是有了 `Lambda` 版。

## 3. `LambdaQueryWrapper`（推荐）

```java
@Test
void testLambdaQueryWrapper() {
    LambdaQueryWrapper<Car> wrapper = new LambdaQueryWrapper<>();
    wrapper.select(Car::getId, Car::getCarNum, Car::getBrand, Car::getGuidePrice)
           .like(Car::getBrand, "宝")
           .gt(Car::getGuidePrice, 20.0);

    List<Car> cars = carMapper.selectList(wrapper);
    cars.forEach(System.out::println);
}
```

- 用**方法引用**代替字符串：`Car::getBrand` → 自动解析成列名 `brand`。
- 属性改名 / 列名变动，**编译期就报错**，这才是真正的安全。

### `Car::getId` 是怎么变成 `"id"` 的？

原理：**序列化 Lambda + 反射**。

```java
import java.lang.invoke.SerializedLambda;
import java.lang.reflect.Method;

class User {
    private Long id;
    public Long getId() { return id; }
}

// 函数式接口必须继承 Serializable
interface MyFunc extends java.io.Serializable {
    Object apply(User user);
}

public class Test {
    public static void main(String[] args) throws Exception {
        MyFunc func = User::getId;

        // 1. Lambda 对应的类里会生成一个 writeReplace 方法
        Method m = func.getClass().getDeclaredMethod("writeReplace");
        m.setAccessible(true);

        // 2. 调用它得到 SerializedLambda，里面封装了 Lambda 的「元数据」
        SerializedLambda lambda = (SerializedLambda) m.invoke(func);

        // 3. 从实现方法名 "getId" 反推属性名 "id"
        String methodName = lambda.getImplMethodName();
        String fieldName = methodName.substring(3, 4).toLowerCase() + methodName.substring(4);
        System.out.println("字段名: " + fieldName);   // id
    }
}
```

MP 内部由 `LambdaUtils` 拿到「实现方法名 + 实现类」，再从 `TableInfo` 里查出对应的列名。
**所以：实体类必须有标准 getter、有无参构造**，否则解析不到列名。

## 4. `UpdateWrapper` / `LambdaUpdateWrapper`

### 4.1 普通更新：`QueryWrapper` 就够了

需求：把 `宝马535` 的指导价改成 10 万。

```sql
update t_car set guide_price = 10.0 where brand = '宝马535';
```

```java
@Test
void testUpdateByWrapper() {
    Car car = new Car();
    car.setGuidePrice(10.0);

    QueryWrapper<Car> wrapper = new QueryWrapper<Car>().eq("brand", "宝马535");
    carMapper.update(car, wrapper);      // 第一个参数：要更新的内容
}
```

Lambda 版：

```java
LambdaQueryWrapper<Car> wrapper = new LambdaQueryWrapper<Car>()
        .eq(Car::getBrand, "宝马535");
carMapper.update(car, wrapper);
```

### 4.2 `set` 特殊时：必须用 `UpdateWrapper`

需求：所有 `宝马535` **涨价 5 万**（`guide_price = guide_price + 5`）。

```sql
update t_car set guide_price = guide_price + 5 where brand = '宝马535';
```

`set` 右边是**列运算**，实体类塞不进去，只能用 `setSql`：

```java
@Test
void testUpdateWrapper() {
    UpdateWrapper<Car> wrapper = new UpdateWrapper<>();
    wrapper.setSql("guide_price = guide_price + 5")
           .eq("brand", "宝马535");
    carMapper.update(wrapper);          // 注意：只有一个参数！
}
```

```java
// Lambda 版
LambdaUpdateWrapper<Car> wrapper = new LambdaUpdateWrapper<>();
wrapper.setSql("guide_price = guide_price + 5")
       .eq(Car::getBrand, "宝马535");
carMapper.update(wrapper);
```

**`update` 的两个重载**

| 重载 | 用法 |
| --- | --- |
| `update(T entity, Wrapper<T> wrapper)` | 用实体类的**非 null** 字段拼 `set` |
| `update(Wrapper<T> wrapper)` | 只用 wrapper 里的 `set` / `setSql` |

### 4.3 把字段更新为 `null`

```java
// 默认 update-strategy=not_null，实体类里设 null 不会更新
// 想置空，必须用 Wrapper 的 set
new LambdaUpdateWrapper<Car>()
        .set(Car::getBrand, null)
        .eq(Car::getId, 1L);
```

## 5. 条件构造器速查表

| 方法 | SQL |
| --- | --- |
| `eq` / `ne` | `= ` / `<>` |
| `gt` / `ge` / `lt` / `le` | `>` / `>=` / `<` / `<=` |
| `like` / `likeLeft` / `likeRight` | `like '%x%'` / `'%x'` / `'x%'` |
| `notLike` | `not like` |
| `in` / `notIn` | `in (...)` |
| `between` / `notBetween` | `between a and b` |
| `isNull` / `isNotNull` | `is null` / `is not null` |
| `orderByAsc` / `orderByDesc` | `order by x asc/desc` |
| `groupBy` / `having` | `group by` / `having` |
| `and` / `or` / `nested` | 拼接括号与逻辑关系 |
| `select` | 指定查询列 |
| `last` | 直接拼在 SQL 末尾（**慎用，有注入风险**） |

**条件成立才拼接**（每个方法都有带 `boolean condition` 的重载）：

```java
wrapper.eq(StringUtils.isNotBlank(brand), Car::getBrand, brand)
       .gt(price != null, Car::getGuidePrice, price);
```

这就是 MP 版的「动态 SQL」，比 XML 里一堆 `<if>` 简洁得多。

## 6. 自定义 SQL：Wrapper + XML 组合

有些 SQL 太复杂（多表、聚合），不适合用 Wrapper 表达，但又想复用 Wrapper 的条件。
做法：**Java 里只构造 Wrapper，SQL 写在 XML 里**。

**第一步：Java 只造条件**

```java
@Test
void testCustomSql() {
    UpdateWrapper<Car> wrapper = new UpdateWrapper<>();
    wrapper.eq("brand", "宝马535");
    carMapper.updateByCustomSql(wrapper, 5.0);
}
```

**第二步：Mapper 接口**

```java
public interface CarMapper extends BaseMapper<Car> {
    void updateByCustomSql(@Param("ew") UpdateWrapper<Car> wrapper,
                           @Param("amount") Double amount);
}
```

> `@Param("ew")` 里的 **`ew` 是固定写法**（也可以用 MP 常量 `Constants.WRAPPER` 代替）。

**第三步：XML**

```xml
<mapper namespace="com.jkweilai.mp.mapper.CarMapper">
    <update id="updateByCustomSql">
        update t_car
        set guide_price = guide_price + #{amount}
        ${ew.customSqlSegment}
    </update>
</mapper>
```

> **`${ew.customSqlSegment}` 也是固定写法**，它会展开成 `where (条件)`（**自带 `where` 关键字**）。
> 这里必须用 `${}` —— 它拼的是 SQL 片段，不是值。

## 7. `IService`：MP 连 Service 层也给了

MP 不只给持久层，还给了 service 层：**`IService<T>` 接口 + `ServiceImpl<M, T>` 实现**。

### 7.1 不继承 `IService` 时，service 长什么样

```java
public interface CarService {
    int save(Car car);
    int removeById(Long id);
    int updateById(Car car);
    Car getById(Long id);
    List<Car> list();
}

@Service
public class CarServiceImpl implements CarService {
    @Autowired
    private CarMapper carMapper;

    @Override public int save(Car car)        { return carMapper.insert(car); }
    @Override public int removeById(Long id)  { return carMapper.deleteById(id); }
    @Override public int updateById(Car car)  { return carMapper.updateById(car); }
    @Override public Car getById(Long id)     { return carMapper.selectById(id); }
    @Override public List<Car> list()         { return carMapper.selectList(null); }
}
```

**结论**：没有复杂业务时，service 就是「注入 mapper → 转调」，代码完全是模板 —— MP 把这层也自动化了。

### 7.2 两步接入

**第一步：接口继承 `IService<T>`**

```java
public interface CarService extends IService<Car> {
    // 需要额外业务方法就在这里加
}
```

**第二步：实现类继承 `ServiceImpl<Mapper, T>` 并实现接口**

```java
@Service
public class CarServiceImpl extends ServiceImpl<CarMapper, Car> implements CarService {
}
```

**为什么两个都要**：

- `implements CarService`：Controller 面向接口编程，`IService` 里的方法要能被调用。
- `extends ServiceImpl<CarMapper, Car>`：**MP 在这里给了默认实现**，不继承就得自己实现 `IService` 的几十个方法。
- `ServiceImpl` 内部有个 `baseMapper` 字段（指向 `CarMapper`），需要写自定义 SQL 时直接用它：

```java
baseMapper.reduction(id, price);
```

> `IService` 的方法前缀是 `save/remove/update/get/list/page/count`，
> 正好对应 `BaseMapper` 的 `insert/delete/update/select`，只是**语义化**了一层。

## 8. `IService` 常用方法

### 8.1 新增

| 方法 | 说明 |
| --- | --- |
| `save(T)` | 保存一条 |
| `saveBatch(Collection<T>)` | 批量保存（底层 JDBC 批处理） |
| `saveOrUpdate(T)` | **有 id 就更新，没 id 就插入**（按 id 判断） |

### 8.2 删除

| 方法 | 说明 |
| --- | --- |
| `removeById(Serializable)` | 按主键删除 |
| `removeByIds(Collection<?>)` | 按多个主键删，底层 `in (id1, id2, id3)` |
| `removeBatchByIds(Collection<?>)` | 按多个主键删，底层走 **JDBC `addBatch`**，数据量大时更快 |
| `remove(Wrapper)` | 按条件删 |

> `removeByIds` 是把 id 拼成 `in` 一条 SQL；`removeBatchByIds` 是一条条 `delete` 但走批处理。
> 数据量小的时候差不多，几十万条时后者更稳（不会造出超长 SQL）。

### 8.3 修改

| 方法 | 说明 |
| --- | --- |
| `updateById(T)` | 按主键更新（null 字段不更新） |
| `updateBatchById(Collection<T>)` | 按主键批量更新 |
| `update(Wrapper)` | 按条件更新（配合 `LambdaUpdateWrapper`） |

### 8.4 查询

| 分类 | 方法 |
| --- | --- |
| 查一个 | `getById`、`getOne(Wrapper)`、`getOne(Wrapper, false)`（查不到不抛异常） |
| 查多个 | `list()`、`list(Wrapper)`、`listByIds(Collection)` |
| 查数量 | `count()`、`count(Wrapper)` |
| 分页 | `page(Page)`、`page(Page, Wrapper)`（需装分页插件） |
| 复杂条件 | `lambdaQuery()`、`lambdaUpdate()`、`query()`、`update()` |

> **提示**：按主键操作优先用 `getById`/`updateById`/`removeById`；
> 条件复杂时再用 `Wrapper` 系列，别一上来就 `list(wrapper).get(0)`。

## 9. 业务实战：五个 RESTful 接口

| 编号 | 接口 | 请求方式 | 路径 | 参数 | 返回 |
| --- | --- | --- | --- | --- | --- |
| 1 | 新增汽车 | POST | `/api/cars` | CarDTO | 无 |
| 2 | 删除汽车 | DELETE | `/api/cars/{id}` | id | 无 |
| 3 | 按 id 查询 | GET | `/api/cars/{id}` | id | CarVO |
| 4 | 按 id 批量查询 | GET | `/api/cars?id=1,2,3` | id 集合 | List&lt;CarVO&gt; |
| 5 | 按 id 降价 | PUT | `/api/cars/{id}/reduction/{price}` | id、额度 | 无 |

技术栈：**Spring Boot + MyBatis-Plus + Knife4j(Swagger) + Hutool + Lombok**。

### 9.1 依赖与配置

```xml
<!-- 接口文档 -->
<dependency>
  <groupId>com.github.xiaoymin</groupId>
  <artifactId>knife4j-openapi3-jakarta-spring-boot-starter</artifactId>
  <version>4.5.0</version>
</dependency>
<!-- MyBatis-Plus（Spring Boot 3） -->
<dependency>
  <groupId>com.baomidou</groupId>
  <artifactId>mybatis-plus-spring-boot3-starter</artifactId>
  <version>3.5.11</version>
</dependency>
<!-- Hutool：BeanUtil.copyProperties / copyToList -->
<dependency>
  <groupId>cn.hutool</groupId>
  <artifactId>hutool-all</artifactId>
  <version>5.8.37</version>
</dependency>
```

```yaml
spring:
  datasource:
    driver-class-name: com.mysql.cj.jdbc.Driver
    url: jdbc:mysql://localhost:3306/mybatis?rewriteBatchedStatements=true
    username: root
    password: root
  mvc:
    pathmatch:
      matching-strategy: ant_path_matcher

knife4j:
  enable: true
  group:
    default:
      group-name: default
      api-rule: package
      api-rule-resources:
        - com.jkweilai.mp.controller
```

> 文档地址：`http://localhost:8080/doc.html`。

### 9.2 PO / DTO / VO 的分工（很重要）

| 类型 | 用途 | 特点 |
| --- | --- | --- |
| **PO**（实体类） | 对应数据库表 | 不参与接口文档，**不加** `@Schema` |
| **DTO** | 接收入参 | **不含 id**（自增生成）、`requiredMode`、`allowableValues` |
| **VO** | 返回出参 | **含 id**、不需要 `requiredMode` / `allowableValues` |

```java
// DTO：只接收前端提交的数据
@Data
@Schema(description = "汽车信息")
public class CarDTO {
    @Schema(description = "车牌号", example = "京A88888",
            requiredMode = Schema.RequiredMode.REQUIRED)
    private String carNum;

    @Schema(description = "品牌", example = "宝马535Li",
            requiredMode = Schema.RequiredMode.REQUIRED)
    private String brand;

    @Schema(description = "厂商指导价（单位：万）", example = "50.00", multipleOf = 0.01,
            requiredMode = Schema.RequiredMode.REQUIRED)
    private BigDecimal guidePrice;

    @Schema(description = "汽车类型", example = "燃油车",
            allowableValues = {"燃油车", "新能源", "氢能源"},
            requiredMode = Schema.RequiredMode.REQUIRED)
    private String carType;
}
```

```java
@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
@Tag(name = "汽车信息管理", description = "对汽车信息进行增删改查")
public class CarController {

    private final CarService carService;

    @PostMapping("/cars")
    @Operation(summary = "新增汽车", description = "新增汽车信息，所有字段为必填项")
    public void add(@RequestBody CarDTO carDTO) {
        Car car = BeanUtil.copyProperties(carDTO, Car.class);   // DTO → PO
        carService.save(car);
    }

    @DeleteMapping("/cars/{id}")
    @Operation(summary = "删除汽车信息")
    public void removeById(@PathVariable Long id) {
        carService.removeById(id);
    }

    @GetMapping("/cars/{id}")
    @Operation(summary = "查询汽车信息")
    public CarVO getCarById(@PathVariable Long id) {
        Car car = carService.getById(id);
        return BeanUtil.copyProperties(car, CarVO.class);       // PO → VO
    }

    @GetMapping("/cars")
    @Operation(summary = "根据id批量查询")
    // Spring Boot 自动支持 ?id=1,2,3 与 ?id=1&id=2 两种写法
    public List<CarVO> getCars(@RequestParam("id") List<Long> ids) {
        return BeanUtil.copyToList(carService.listByIds(ids), CarVO.class);
    }
}
```

### 9.3 复杂业务：降价（事务 + 校验）

```java
@Override
@Transactional(rollbackFor = Exception.class)
public void reduction(Long id, BigDecimal price) {
    Car car = getById(id);
    if (car == null) {
        throw new RuntimeException("您操作降价的汽车不存在，汽车id=" + id);
    }
    if (price.compareTo(car.getGuidePrice()) > 0) {
        throw new RuntimeException("降价后的价格不能小于0");
    }
    // baseMapper 是 ServiceImpl 内置的引用，指向 Dao
    baseMapper.reduction(id, price);
}
```

```java
public interface CarDao extends BaseMapper<Car> {
    @Update("update t_car set guide_price = guide_price - #{price} where id = #{id}")
    void reduction(@Param("id") Long id, @Param("price") BigDecimal price);
}
```

## 10. `lambdaQuery()` 与 `lambdaUpdate()`

`IService` 提供的两个「链式入口」，**不用 new Wrapper**，代码更短。

### 10.1 `lambdaQuery()`：多条件动态查询

需求：按品牌模糊、价格区间、类型查询，**用户填了才查**。

```java
@Override
public List<Car> queryByMultiCondition(CarQuery carQuery) {
    String brand = carQuery.getBrand();
    String carType = carQuery.getCarType();
    BigDecimal minPrice = carQuery.getMinPrice();
    BigDecimal maxPrice = carQuery.getMaxPrice();

    // 不调用 select() 时，默认返回实体里所有 @TableField 标注的字段
    return lambdaQuery()
            .like(StringUtils.isNotBlank(brand), Car::getBrand, brand)
            .eq(StringUtils.isNotBlank(carType), Car::getCarType, carType)
            .ge(minPrice != null, Car::getGuidePrice, minPrice)
            .le(maxPrice != null, Car::getGuidePrice, maxPrice)
            .list();
}
```

Controller 侧（GET 查询把条件放请求行，`@ParameterObject` 只是让 Swagger 把对象字段展开显示，**与 Spring MVC 无关**）：

```java
@GetMapping("/cars/conditions")
@Operation(summary = "多条件查询汽车")
public List<CarVO> queryByMultiCondition(@ParameterObject CarQuery carQuery) {
    return BeanUtil.copyToList(carService.queryByMultiCondition(carQuery), CarVO.class);
}
```

### 10.2 `lambdaUpdate()`：复杂更新 + 乐观锁

需求：降价后若低于 10 万，把类型改为「低端车」。

```java
BigDecimal currentPrice = car.getGuidePrice().subtract(price);

lambdaUpdate()
        .set(Car::getGuidePrice, currentPrice)
        .set(currentPrice.compareTo(new BigDecimal("10")) < 0, Car::getCarType, "低端车")
        .eq(Car::getId, id)
        .eq(Car::getGuidePrice, car.getGuidePrice())   // 乐观锁：价格没被别人改过才更新
        .update();
```

> **`事务 + 乐观锁` 才能保证「查 → 算 → 改」的原子性。**
> 只 `update` 而不带旧值条件，并发下会出现「两次降价只生效一次」或「覆盖别人的修改」。

## 11. 批量新增的三种写法（性能差 10 倍以上）

```java
// ① 逐条 save：1 万条 → 每次一个事务、一次网络往返，最慢
for (long i = 1; i <= 10000; i++) {
    carService.save(buildCar(i));
}

// ② saveBatch 分批：每 100 条打包一次，快很多
List<Car> cars = new ArrayList<>(100);
for (long i = 1; i <= 10000; i++) {
    cars.add(buildCar(i));
    if (i % 100 == 0) {
        carService.saveBatch(cars);
        cars.clear();
    }
}
```

```yaml
# ③ 再给 MySQL 驱动加参数，批量插入再快一截
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/mybatis?rewriteBatchedStatements=true
```

`rewriteBatchedStatements=true` 的作用：把驱动原本「一条条发 insert」的批处理，
**在驱动层改写成一条 `insert into ... values (...),(...),(...)`**，减少网络往返。
这是 **MySQL 驱动的能力，不是 MP 的功能**，但它是批量插入提速的关键一步。

## 12. 本篇小结

1. `QueryWrapper` / `UpdateWrapper` 是**字符串列名**版，`Lambda*` 是**方法引用**版 —— **优先用 Lambda 版**。
2. `set` 表达式特殊（列运算、置 null）时用 `UpdateWrapper.setSql` / `set`。
3. 每个条件方法都有 `boolean condition` 重载，这就是 MP 版动态 SQL。
4. 自定义 SQL：`@Param("ew")` + `${ew.customSqlSegment}`。
5. `IService` + `ServiceImpl` 两步接入；`baseMapper` 拿 mapper；`lambdaQuery/lambdaUpdate` 写复杂条件。
6. 批量插入：`saveBatch` 分批 + `rewriteBatchedStatements=true`。


